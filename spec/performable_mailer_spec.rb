require 'helper'

class MyMailer < ActionMailer::Base
  def signup(email)
    mail to: email, subject: 'Delaying Emails', from: 'delayedjob@example.com', body: 'Delaying Emails Body'
  end
end

describe ActionMailer::Base do
  describe 'delay' do
    it 'enqueues a PerformableEmail job' do
      expect {
        job = MyMailer.delay.signup('john@example.com')
        expect(job.payload_object.class).to eq(Delayed::PerformableMailer)
        expect(job.payload_object.method_name).to eq(:signup)
        expect(job.payload_object.args).to eq(['john@example.com'])
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

  describe Delayed::PerformableMailer do
    describe 'perform' do
      it 'calls the method and #deliver on the mailer' do
        email = double('email', deliver: true)
        mailer_class = double('MailerClass', signup: email)
        mailer = described_class.new(mailer_class, :signup, ['john@example.com'])

        expect(mailer_class).to receive(:signup).with('john@example.com')
        expect(email).to receive(:deliver)
        mailer.perform
      end
    end
  end
end

if defined?(ActionMailer::Parameterized::Mailer)
  describe ActionMailer::Parameterized::Mailer do
    describe 'delay' do
      it 'enqueues a PerformableEmail job' do
        expect {
          job = MyMailer.with(foo: 1, bar: 2).delay.signup('john@example.com')
          expect(job.payload_object.class).to eq(Delayed::PerformableMailer)
          expect(job.payload_object.object.class).to eq(described_class)
          expect(job.payload_object.object.instance_variable_get('@mailer')).to eq(MyMailer)
          expect(job.payload_object.object.instance_variable_get('@params')).to eq(foo: 1, bar: 2)
          expect(job.payload_object.method_name).to eq(:signup)
          expect(job.payload_object.args).to eq(['john@example.com'])
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
