require 'helper'

describe Delayed::PerformableMailer do
  let(:mailer_class) do
    Class.new(ActionMailer::Base) do
      cattr_accessor(:emails) { [] }

      def signup(email, beta_tester: false)
        mail to: email, subject: "Delaying Emails (beta: #{beta_tester})", from: 'delayedjob@example.com', body: 'Delaying Emails Body'
      end
    end
  end

  before do
    stub_const('MyMailer', mailer_class)
  end

  describe 'perform' do
    it 'calls the method and #deliver on the mailer' do
      mailer = MyMailer.new
      email = double('email', deliver: true)
      allow(mailer).to receive(:mail).and_return(email)
      mailer_job = described_class.new(mailer, :signup, ['john@example.com'], {})

      expect(email).to receive(:deliver)
      mailer_job.perform
    end
  end

  describe ActionMailer::Base do
    describe 'delay' do
      it 'enqueues a PerformableEmail job' do
        expect {
          job = MyMailer.delay.signup('john@example.com', beta_tester: true)
          expect(job.payload_object.class).to eq(Delayed::PerformableMailer)
          expect(job.payload_object.method_name).to eq(:signup)
          expect(job.payload_object.args).to eq(['john@example.com'])
          expect(job.payload_object.kwargs).to eq(beta_tester: true)
        }.to change { Delayed::Job.count }.by(1)
      end
    end

    describe 'delay on a mail object' do
      it 'raises an exception' do
        expect {
          MyMailer.signup('john@example.com').delay
        }.to raise_error(RuntimeError)
      end
    end
  end

  if defined?(ActionMailer::Parameterized::Mailer)
    describe ActionMailer::Parameterized::Mailer do
      describe 'delay' do
        it 'enqueues a PerformableEmail job' do
          expect {
            job = MyMailer.with(foo: 1, bar: 2).delay.signup('john@example.com', beta_tester: false)
            expect(job.payload_object.class).to eq(Delayed::PerformableMailer)
            expect(job.payload_object.object.class).to eq(described_class)
            expect(job.payload_object.object.instance_variable_get(:@mailer)).to eq(MyMailer)
            expect(job.payload_object.object.instance_variable_get(:@params)).to eq(foo: 1, bar: 2)
            expect(job.payload_object.method_name).to eq(:signup)
            expect(job.payload_object.args).to eq(['john@example.com'])
            expect(job.payload_object.kwargs).to eq(beta_tester: false)
          }.to change { Delayed::Job.count }.by(1)
        end
      end

      describe 'delay on a mail object' do
        it 'raises an exception' do
          expect {
            MyMailer.with(foo: 1, bar: 2).signup('john@example.com').delay
          }.to raise_error(RuntimeError)
        end
      end
    end
  end
end
