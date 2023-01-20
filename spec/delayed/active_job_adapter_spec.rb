require 'helper'

RSpec.describe Delayed::ActiveJobAdapter do
  let(:arbitrary_time) do
    Time.parse('2021-01-05 03:34:33 UTC')
  end
  let(:queue_adapter) { :delayed }
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
    ActiveJob::Base.queue_adapter = queue_adapter
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter_was
  end

  it 'serializes a JobWrapper in the handler with expected fields' do
    Timecop.freeze('2023-01-20T18:52:29Z') do
      JobClass.perform_later
    end

    Delayed::Job.last.tap do |dj|
      expect(dj.handler.lines).to match [
        "--- !ruby/object:Delayed::JobWrapper\n",
        "job_data:\n",
        "  job_class: JobClass\n",
        /  job_id: '?#{dj.payload_object.job_id}'?\n/,
        "  provider_job_id: \n",
        "  queue_name: default\n",
        "  priority: \n",
        "  arguments: []\n",
        "  executions: 0\n",
        ("  exception_executions: {}\n" if ActiveJob::VERSION::MAJOR >= 6),
        "  locale: en\n",
        ("  timezone: \n" if ActiveJob::VERSION::MAJOR >= 6),
        ("  enqueued_at: '2023-01-20T18:52:29Z'\n" if ActiveJob::VERSION::MAJOR >= 6),
      ].compact
    end
  end

  it 'deserializes even if the underlying job class is not defined' do
    JobClass.perform_later

    Delayed::Job.last.tap do |dj|
      dj.handler = dj.handler.gsub('JobClass', 'MissingJobClass')
      expect { dj.payload_object }.not_to raise_error
      expect { dj.payload_object.job_id }.to raise_error(NameError, 'uninitialized constant MissingJobClass')
    end
  end

  describe '.set' do
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

  describe '.perform_later' do
    it 'applies the default ActiveJob queue and priority' do
      JobClass.perform_later

      expect(Delayed::Job.last.queue).to eq('default')
      expect(Delayed::Job.last.priority).to eq(10)
    end

    it 'supports overriding queue and priority' do
      JobClass.set(queue: 'a', priority: 3).perform_later

      expect(Delayed::Job.last.queue).to eq('a')
      expect(Delayed::Job.last.priority).to eq(3)
    end

    context 'when all default queues and priorities are nil' do
      before do
        ActiveJob::Base.queue_name = nil
        ActiveJob::Base.priority = nil
        Delayed::Worker.default_queue_name = nil
        Delayed::Worker.default_priority = nil
      end

      it 'applies no queue or priority' do
        JobClass.perform_later

        expect(Delayed::Job.last.queue).to be_nil
        expect(Delayed::Job.last.priority).to eq(0)
      end

      it 'supports overriding queue and priority' do
        JobClass.set(queue: 'a', priority: 3).perform_later

        expect(Delayed::Job.last.queue).to eq('a')
        expect(Delayed::Job.last.priority).to eq(3)
      end
    end

    context 'when there is a default Delayed queue and priority, but not ActiveJob' do
      before do
        ActiveJob::Base.queue_name = nil
        ActiveJob::Base.priority = nil
        Delayed::Worker.default_queue_name = 'dj_default'
        Delayed::Worker.default_priority = 99
      end

      it 'applies the default Delayed queue and priority' do
        JobClass.perform_later

        expect(Delayed::Job.last.queue).to eq('dj_default')
        expect(Delayed::Job.last.priority).to eq(99)
      end

      it 'supports overriding queue and priority' do
        JobClass.set(queue: 'a', priority: 3).perform_later

        expect(Delayed::Job.last.queue).to eq('a')
        expect(Delayed::Job.last.priority).to eq(3)
      end
    end

    context 'when ActiveJob specifies a different default queue and priority' do
      before do
        ActiveJob::Base.queue_name = 'aj_default'
        ActiveJob::Base.priority = 11
      end

      it 'applies the default ActiveJob queue and priority' do
        JobClass.perform_later

        expect(Delayed::Job.last.queue).to eq('aj_default')
        expect(Delayed::Job.last.priority).to eq(11)
      end

      it 'supports overriding queue and priority' do
        JobClass.set(queue: 'a', priority: 3).perform_later

        expect(Delayed::Job.last.queue).to eq('a')
        expect(Delayed::Job.last.priority).to eq(3)
      end
    end

    context 'when ActiveJob uses queue_with_priority' do
      let(:job_class) do
        Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob
          queue_with_priority Delayed::Priority.reporting

          def perform; end
        end
      end

      it 'applies the specified priority' do
        JobClass.perform_later

        expect(Delayed::Job.last.priority).to eq(30)
      end
    end

    context 'when ActiveJob has both positional and keyword arguments' do
      let(:job_class) do
        Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob
          cattr_accessor(:result)

          def perform(arg, kwarg:)
            self.class.result = [arg, kwarg]
          end
        end
      end

      it 'passes arguments through to the perform method' do
        JobClass.perform_later('foo', kwarg: 'bar')

        Delayed::Worker.new.work_off
        expect(JobClass.result).to eq %w(foo bar)
      end
    end

    context 'when using the ActiveJob test adapter' do
      let(:queue_adapter) { :test }

      it 'applies the default ActiveJob queue and priority' do
        JobClass.perform_later

        if ActiveJob.gem_version < Gem::Version.new('6')
          expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, queue: 'default')
        else
          expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, 'priority' => nil, queue: 'default')
        end
      end

      context 'when ActiveJob specifies a different default queue and priority' do
        before do
          ActiveJob::Base.queue_name = 'aj_default'
          ActiveJob::Base.priority = 11
        end

        it 'applies the default ActiveJob queue and priority' do
          JobClass.perform_later

          if ActiveJob.gem_version < Gem::Version.new('6')
            expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, queue: 'aj_default')
          else
            expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, 'priority' => 11, queue: 'aj_default')
          end
        end
      end

      it 'supports overriding queue, priority, and wait_until' do
        JobClass.set(queue: 'a', priority: 3, wait_until: arbitrary_time).perform_later

        if ActiveJob.gem_version < Gem::Version.new('6')
          expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, queue: 'a', at: arbitrary_time.to_f)
        else
          expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, 'priority' => 3, queue: 'a', at: arbitrary_time.to_f)
        end
      end
    end
  end
end
