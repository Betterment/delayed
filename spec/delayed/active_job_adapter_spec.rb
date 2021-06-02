require 'helper'

RSpec.describe Delayed::ActiveJobAdapter do
  let(:job_class) do
    Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob
      def perform; end
    end
  end

  before do
    stub_const 'JobClass', job_class
  end

  around do |example|
    adapter_was = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :delayed
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter_was
  end

  describe '.set' do
    let(:arbitrary_time) do
      Time.parse('2021-01-05 03:34:33 UTC')
    end

    it 'supports priority as an integer' do
      JobClass.set(priority: 43).perform_later

      expect(Delayed::Job.last.priority).to be_reporting
      expect(Delayed::Job.last.priority).to eq(43)
    end

    it 'supports priority as a Delayed::Priority' do
      JobClass.set(priority: Delayed::Priority.eventual).perform_later

      expect(Delayed::Job.last.priority).to be_eventual
      expect(Delayed::Job.last.priority).to eq(20)
    end

    it 'supports priority as a symbol' do
      JobClass.set(priority: :eventual).perform_later

      expect(Delayed::Job.last.priority).to be_eventual
      expect(Delayed::Job.last.priority).to eq(20)
    end

    it 'raises an error when run_at is used' do
      expect { JobClass.set(run_at: arbitrary_time).perform_later }
        .to raise_error(/`:run_at` is not supported./)
    end

    it 'converts wait_until to run_at' do
      JobClass.set(wait_until: arbitrary_time).perform_later

      expect(Delayed::Job.last.run_at).to eq('2021-01-05 03:34:33 UTC')
    end

    context 'when running at a specific time' do
      around do |example|
        Timecop.freeze(arbitrary_time) { example.run }
      end

      it 'adds wait input to current time' do
        JobClass.set(wait: (1.day + 1.hour + 1.minute)).perform_later

        expect(Delayed::Job.last.run_at).to eq('2021-01-06 04:35:33 UTC')
      end
    end

    context 'when the Delayed::Job class supports arbitrary attributes' do
      before do
        Delayed::Job.class_eval do
          def foo=(value)
            self.queue = "foo-#{value}"
          end
        end
      end

      after do
        Delayed::Job.undef_method(:foo=)
      end

      it 'calls the expected setter' do
        JobClass.set(foo: 'bar').perform_later

        expect(Delayed::Job.last.queue).to eq('foo-bar')
      end
    end

    context 'when the ActiveJob performable defines a max_attempts' do
      let(:job_class) do
        Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob
          def perform; end

          def max_attempts
            3
          end
        end
      end

      it 'surfaces max_attempts on the JobWrapper' do
        JobClass.perform_later

        expect(Delayed::Job.last.max_attempts).to eq 3
      end
    end

    context 'when the ActiveJob performable defines an arbitrary method' do
      let(:job_class) do
        Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob
          def perform; end

          def arbitrary_method
            'hello'
          end
        end
      end

      it 'surfaces arbitrary_method on the JobWrapper' do
        JobClass.perform_later

        expect(Delayed::Job.last.payload_object.arbitrary_method).to eq 'hello'
      end
    end
  end
end
