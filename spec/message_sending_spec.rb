require 'helper'

describe Delayed::MessageSending do
  it 'does not include ClassMethods along with MessageSending' do
    expect { ClassMethods }.to raise_error(NameError)
    expect(defined?(String::ClassMethods)).to eq(nil)
  end

  describe 'handle_asynchronously' do
    let(:test_class) do
      Class.new do
        def tell!(_arg, _kwarg:); end
        handle_asynchronously :tell!
      end
    end

    it 'aliases original method' do
      expect(test_class.new).to respond_to(:tell_without_delay!)
      expect(test_class.new).to respond_to(:tell_with_delay!)
    end

    it 'creates a PerformableMethod' do
      obj = test_class.new
      expect {
        job = obj.tell!('a', kwarg: 'b')
        expect(job.payload_object.class).to eq(Delayed::PerformableMethod)
        expect(job.payload_object.method_name).to eq(:tell_without_delay!)
        expect(job.payload_object.args).to eq(['a'])
        expect(job.payload_object.kwargs).to eq(kwarg: 'b')
      }.to change { Delayed::Job.count }.by(1)
    end

    describe 'with options' do
      class Fable
        cattr_accessor :importance
        def tell; end
        handle_asynchronously :tell, priority: proc { importance }
      end

      it 'sets the priority based on the Fable importance' do
        Fable.importance = 10
        job = Fable.new.tell
        expect(job.priority).to eq(10)

        Fable.importance = 20
        job = Fable.new.tell
        expect(job.priority).to eq(20)
      end

      describe 'using a proc with parameters' do
        class Yarn
          attr_accessor :importance

          def spin; end
          handle_asynchronously :spin, priority: proc { |y| y.importance }
        end

        it 'sets the priority based on the Fable importance' do
          job = Yarn.new.tap { |y| y.importance = 10 }.spin
          expect(job.priority).to eq(10)

          job = Yarn.new.tap { |y| y.importance = 20 }.spin
          expect(job.priority).to eq(20)
        end
      end
    end
  end

  context 'delay' do
    let(:fairy_tail_class) do
      Class.new do
        attr_accessor :happy_ending

        def self.princesses; end

        def tell(arg, kwarg:)
          @happy_ending = [arg, kwarg]
        end
      end
    end

    before do
      stub_const('FairyTail', fairy_tail_class)
    end

    after do
      Delayed::Worker.default_queue_name = nil
    end

    it 'creates a new PerformableMethod job' do
      expect {
        job = FairyTail.new.delay.tell('arg', kwarg: 'kwarg')
        expect(job.payload_object.class).to eq(Delayed::PerformableMethod)
        expect(job.payload_object.method_name).to eq(:tell)
        expect(job.payload_object.args).to eq(['arg'])
        expect(job.payload_object.kwargs).to eq(kwarg: 'kwarg')
      }.to change { Delayed::Job.count }.by(1)
    end

    it 'sets default priority' do
      Delayed::Worker.default_priority = 99
      job = FairyTail.delay.to_s
      expect(job.priority).to eq(99)
    end

    it 'sets default queue name' do
      Delayed::Worker.default_queue_name = 'abbazabba'
      job = FairyTail.delay.to_s
      expect(job.queue).to eq('abbazabba')
    end

    it 'sets job options' do
      run_at = Time.parse('2010-05-03 12:55 AM')
      job = FairyTail.delay(priority: 20, run_at: run_at).to_s
      expect(job.run_at).to eq(run_at)
      expect(job.priority).to eq(20)
    end

    it 'does not delay the job when delay_jobs is false' do
      Delayed::Worker.delay_jobs = false
      fairy_tail = FairyTail.new
      expect {
        expect {
          fairy_tail.delay.tell('a', kwarg: 'b')
        }.to change { fairy_tail.happy_ending }.from(nil).to %w(a b)
      }.not_to(change { Delayed::Job.count })
    end

    it 'does delay the job when delay_jobs is true' do
      Delayed::Worker.delay_jobs = true
      fairy_tail = FairyTail.new
      expect {
        expect {
          fairy_tail.delay.tell('a', kwarg: 'b')
        }.not_to change { fairy_tail.happy_ending }
      }.to change { Delayed::Job.count }.by(1)
    end

    it 'does delay when delay_jobs is a proc returning true' do
      Delayed::Worker.delay_jobs = ->(_job) { true }
      fairy_tail = FairyTail.new
      expect {
        expect {
          fairy_tail.delay.tell('a', kwarg: 'b')
        }.not_to change { fairy_tail.happy_ending }
      }.to change { Delayed::Job.count }.by(1)
    end

    it 'does not delay the job when delay_jobs is a proc returning false' do
      Delayed::Worker.delay_jobs = ->(_job) { false }
      fairy_tail = FairyTail.new
      expect {
        expect {
          fairy_tail.delay.tell('a', kwarg: 'b')
        }.to change { fairy_tail.happy_ending }.from(nil).to %w(a b)
      }.not_to(change { Delayed::Job.count })
    end
  end
end
