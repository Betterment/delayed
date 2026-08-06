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
  let(:enqueued_delayed_jobs) { [] }

  before do
    stub_const 'JobClass', job_class

    next_id = 0
    allow(Delayed::Job).to receive(:enqueue_job) do |options|
      delayed_job = Delayed::Job.new(options)
      next_id += 1
      delayed_job.id = next_id
      enqueued_delayed_jobs << delayed_job
      delayed_job
    end
    allow(Delayed::Job).to receive(:enqueue_all) do |delayed_jobs|
      if Delayed::Job.connection.supports_insert_returning?
        delayed_jobs.each do |delayed_job|
          next_id += 1
          delayed_job.id = next_id
        end
      end
      enqueued_delayed_jobs.concat(delayed_jobs)
      delayed_jobs.size
    end
  end

  around do |example|
    adapter_was = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = queue_adapter
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter_was
  end

  it "does not invoke #deserialize during enqueue" do # rubocop:disable RSpec/NoExpectationExample
    JobClass.include(Module.new do
      def deserialize(*)
        raise "uh oh, deserialize called during enqueue!"
      end
    end)

    JobClass.perform_later
  end

  it 'serializes a JobWrapper in the handler with expected fields' do
    Timecop.freeze('2023-01-20T18:52:29Z') do
      JobClass.perform_later
    end

    enqueued_delayed_jobs.last.tap do |dj|
      expect(dj.handler.lines).to match [
        "--- !ruby/object:Delayed::JobWrapper\n",
        "job_data:\n",
        "  job_class: JobClass\n",
        /  job_id: '?#{dj.payload_object.job_id}'?\n/,
        /  provider_job_id: ?\n/,
        "  queue_name: default\n",
        /  priority: ?\n/,
        "  arguments: []\n",
        "  executions: 0\n",
        "  exception_executions: {}\n",
        "  locale: en\n",
        /  timezone: ?\n/,
        /  enqueued_at: '2023-01-20T18:52:29(\.\d+)?Z'\n/,
        (/  scheduled_at: ?\n/ if ActiveJob.gem_version >= Gem::Version.new('7.1')),
      ].compact
    end
  end

  it 'bubbles out an error if the job fails to serialize' do
    JobClass.class_eval do
      def serialize(*)
        raise "uh oh, serialize failed!"
      end
    end

    expect { JobClass.perform_later }.to raise_error(RuntimeError, "uh oh, serialize failed!")
  end

  it 'bubbles out an error if Delayed::Job.enqueue_job raises (single-job path)' do
    allow(Delayed::Job).to receive(:enqueue_all).and_raise('uh oh, enqueue failed!')

    expect { JobClass.perform_later }.to raise_error(RuntimeError, 'uh oh, enqueue failed!')
  end

  it 'bubbles out an error if Delayed::Job.enqueue_all raises (bulk path)' do
    allow(Delayed::Job).to receive(:enqueue_all).and_raise('uh oh, enqueue failed!')

    expect { ActiveJob::Base.queue_adapter.enqueue_all([JobClass.new]) }
      .to raise_error(RuntimeError, 'uh oh, enqueue failed!')
  end

  context 'when integrated end-to-end (and_call_original)' do
    before do
      allow(Delayed::Job).to receive(:enqueue_job).and_call_original
      allow(Delayed::Job).to receive(:enqueue_all).and_call_original
    end

    it 'deserializes even if the underlying job class is not defined' do
      JobClass.perform_later

      Delayed::Job.last.tap do |dj|
        dj.update!(handler: dj.handler.gsub('JobClass', 'MissingJobClass'))
        expect { dj.payload_object }.not_to raise_error
        expect { dj.payload_object.job_id }.to raise_error(NameError, 'uninitialized constant MissingJobClass')
      end
      expect(Delayed::Worker.new.work_off).to eq([0, 1])
      expect(Delayed::Job.last.last_error).to match(/uninitialized constant MissingJobClass/)
    end

    it 'deserializes even if an underlying argument gid is not defined' do
      ActiveJobJob.perform_later(story: Story.create!)
      Delayed::Job.last.tap do |dj|
        dj.update!(handler: dj.handler.gsub('Story', 'MissingArgumentClass'))
        expect { dj.payload_object }.not_to raise_error
        expect { dj.payload_object.perform_now }.to raise_error(ActiveJob::DeserializationError)
      end
      expect(Delayed::Worker.new.work_off).to eq([0, 1])
      expect(Delayed::Job.last.last_error).to match(/Error while trying to deserialize arguments/)
    end
  end

  describe '.set' do
    it 'supports priority as an integer' do
      JobClass.set(priority: 43).perform_later

      expect(enqueued_delayed_jobs.last.priority).to be_reporting
      expect(enqueued_delayed_jobs.last.priority).to eq(43)
    end

    it 'supports priority as a Delayed::Priority' do
      JobClass.set(priority: Delayed::Priority.eventual).perform_later

      expect(enqueued_delayed_jobs.last.priority).to be_eventual
      expect(enqueued_delayed_jobs.last.priority).to eq(20)
    end

    it 'supports priority as a symbol' do
      JobClass.set(priority: :eventual).perform_later

      expect(enqueued_delayed_jobs.last.priority).to be_eventual
      expect(enqueued_delayed_jobs.last.priority).to eq(20)
    end

    it 'ignores a nil priority, applying the default instead' do
      JobClass.set(priority: nil).perform_later

      expect(enqueued_delayed_jobs.last.priority).to eq(10)
    end

    it 'raises an error when run_at is used' do
      expect { JobClass.set(run_at: arbitrary_time).perform_later }
        .to raise_error(/`:run_at` is not supported./)
    end

    it 'converts wait_until to run_at' do
      JobClass.set(wait_until: arbitrary_time).perform_later

      expect(enqueued_delayed_jobs.last.run_at).to eq('2021-01-05 03:34:33 UTC')
    end

    context 'when running at a specific time' do
      around do |example|
        Timecop.freeze(arbitrary_time) { example.run }
      end

      it 'adds wait input to current time' do
        JobClass.set(wait: (1.day + 1.hour + 1.minute)).perform_later

        expect(enqueued_delayed_jobs.last.run_at).to eq('2021-01-06 04:35:33 UTC')
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

        expect(enqueued_delayed_jobs.last.queue).to eq('foo-bar')
      end
    end

    context 'when using the ActiveJob test adapter' do
      let(:queue_adapter) { :test }

      it 'raises an error when run_at is used' do
        expect { JobClass.set(run_at: arbitrary_time).perform_later }
          .to raise_error(/`:run_at` is not supported./)
      end

      it 'supports priority as a Delayed::Priority' do
        JobClass.set(priority: Delayed::Priority.eventual).perform_later

        expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, 'priority' => 20)
      end

      it 'supports priority as a symbol' do
        JobClass.set(priority: :eventual).perform_later

        expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, 'priority' => 20)
      end

      it 'ignores a nil priority, applying the default instead' do
        JobClass.set(priority: nil).perform_later

        expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, 'priority' => nil)
      end

      it 'captures arbitrary provider attributes without interfering with enqueue' do
        JobClass.set(foo: 'bar').perform_later

        expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, queue: 'default')
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

        expect(enqueued_delayed_jobs.last.max_attempts).to eq 3
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

        expect(enqueued_delayed_jobs.last.payload_object.arbitrary_method).to eq 'hello'
      end
    end
  end

  describe '.perform_later' do
    it 'applies the default ActiveJob queue and priority' do
      JobClass.perform_later

      expect(enqueued_delayed_jobs.last.queue).to eq('default')
      expect(enqueued_delayed_jobs.last.priority).to eq(10)
    end

    it 'supports overriding queue and priority' do
      JobClass.set(queue: 'a', priority: 3).perform_later

      expect(enqueued_delayed_jobs.last.queue).to eq('a')
      expect(enqueued_delayed_jobs.last.priority).to eq(3)
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

        expect(enqueued_delayed_jobs.last.queue).to be_nil
        expect(enqueued_delayed_jobs.last.priority).to eq(0)
      end

      it 'supports overriding queue and priority' do
        JobClass.set(queue: 'a', priority: 3).perform_later

        expect(enqueued_delayed_jobs.last.queue).to eq('a')
        expect(enqueued_delayed_jobs.last.priority).to eq(3)
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

        expect(enqueued_delayed_jobs.last.queue).to eq('dj_default')
        expect(enqueued_delayed_jobs.last.priority).to eq(99)
      end

      it 'supports overriding queue and priority' do
        JobClass.set(queue: 'a', priority: 3).perform_later

        expect(enqueued_delayed_jobs.last.queue).to eq('a')
        expect(enqueued_delayed_jobs.last.priority).to eq(3)
      end
    end

    context 'when ActiveJob specifies a different default queue and priority' do
      before do
        ActiveJob::Base.queue_name = 'aj_default'
        ActiveJob::Base.priority = 11
      end

      it 'applies the default ActiveJob queue and priority' do
        JobClass.perform_later

        expect(enqueued_delayed_jobs.last.queue).to eq('aj_default')
        expect(enqueued_delayed_jobs.last.priority).to eq(11)
      end

      it 'supports overriding queue and priority' do
        JobClass.set(queue: 'a', priority: 3).perform_later

        expect(enqueued_delayed_jobs.last.queue).to eq('a')
        expect(enqueued_delayed_jobs.last.priority).to eq(3)
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

        expect(enqueued_delayed_jobs.last.priority).to eq(30)
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

      before do
        allow(Delayed::Job).to receive(:enqueue_job).and_call_original
        allow(Delayed::Job).to receive(:enqueue_all).and_call_original
      end

      it 'passes arguments through to the perform method' do
        JobClass.perform_later('foo', kwarg: 'bar')

        Delayed::Worker.new.work_off
        expect(JobClass.result).to eq %w(foo bar)
      end
    end

    if ActiveJob.gem_version.release >= Gem::Version.new('7.2')
      context 'when the given job sets enqueue_after_transaction_commit to :always' do
        before do
          JobClass.include ActiveJob::EnqueueAfterTransactionCommit # normally run in an ActiveJob railtie
          JobClass.enqueue_after_transaction_commit = :always
        end

        it 'raises an exception on enqueue' do
          ActiveJob.deprecator.silence do
            expect { JobClass.perform_later }.to raise_error(Delayed::ActiveJobAdapter::UnsafeEnqueueError)
          end
        end
      end

      context 'when the given job sets enqueue_after_transaction_commit to :never' do
        before do
          JobClass.include ActiveJob::EnqueueAfterTransactionCommit # normally run in an ActiveJob railtie
          JobClass.enqueue_after_transaction_commit = :never
        end

        it 'does not raises an exception on enqueue' do
          ActiveJob.deprecator.silence do
            expect { JobClass.perform_later }.not_to raise_error
          end
        end
      end
    end

    if ActiveJob.gem_version.release >= Gem::Version.new('8.0')
      context 'when the given job sets enqueue_after_transaction_commit to true' do
        before do
          JobClass.include ActiveJob::EnqueueAfterTransactionCommit # normally run in an ActiveJob railtie
          JobClass.enqueue_after_transaction_commit = true
        end

        it 'raises an exception on enqueue' do
          expect { JobClass.perform_later }.to raise_error(Delayed::ActiveJobAdapter::UnsafeEnqueueError)
        end
      end

      context 'when the given job sets enqueue_after_transaction_commit to false' do
        before do
          JobClass.include ActiveJob::EnqueueAfterTransactionCommit # normally run in an ActiveJob railtie
          JobClass.enqueue_after_transaction_commit = false
        end

        it 'does not raises an exception on enqueue' do
          expect { JobClass.perform_later }.not_to raise_error
        end
      end
    end

    context 'when using the ActiveJob test adapter' do
      let(:queue_adapter) { :test }

      it 'applies the default ActiveJob queue and priority' do
        JobClass.perform_later

        expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, 'priority' => nil, queue: 'default')
      end

      context 'when ActiveJob specifies a different default queue and priority' do
        before do
          ActiveJob::Base.queue_name = 'aj_default'
          ActiveJob::Base.priority = 11
        end

        it 'applies the default ActiveJob queue and priority' do
          JobClass.perform_later

          expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, 'priority' => 11, queue: 'aj_default')
        end
      end

      it 'supports overriding queue, priority, and wait_until' do
        JobClass.set(queue: 'a', priority: 3, wait_until: arbitrary_time).perform_later

        expect(JobClass.queue_adapter.enqueued_jobs.first).to include(job: JobClass, 'priority' => 3, queue: 'a', at: arbitrary_time.to_f)
      end
    end
  end

  describe 'ActiveJob .retry_on' do
    let(:retry_job_class) do
      Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob
        retry_on(RetryTestError)
        retry_on(RetryTestErrorWithSpecificPriority, priority: 123)

        queue_with_priority 567

        def perform(error_class_name)
          raise error_class_name.constantize
        end
      end
    end

    before do
      allow(Delayed::Job).to receive(:enqueue_job).and_call_original
      allow(Delayed::Job).to receive(:enqueue_all).and_call_original

      stub_const('RetryTestError', Class.new(StandardError))
      stub_const('RetryTestErrorWithSpecificPriority', Class.new(StandardError))
      stub_const('MyRetryJob', retry_job_class)
    end

    context 'when retry_on does not specify a priority' do
      it 're-enqueues a new delayed job with the same priority' do
        MyRetryJob.perform_later('RetryTestError')
        original = Delayed::Job.last

        expect(Delayed::Worker.new.work_off).to eq([1, 0])

        retried = Delayed::Job.last
        expect(retried.id).not_to eq(original.id)
        expect(retried.priority).to eq(567)

        expect(retried.payload_object.job_data['priority']).to be_an(Integer)
        expect(retried.payload_object.job_data['priority']).to eq(567)
      end

      it 'reuses a priority and queue set for the specific job run' do
        MyRetryJob.set(priority: 789, queue: 'fake_queue').perform_later('RetryTestError')

        expect(Delayed::Worker.new.work_off).to eq([1, 0])

        retried = Delayed::Job.last
        expect(retried.priority).to eq(789)
        expect(retried.queue).to eq('fake_queue')
      end

      it 're-enqueues with the current priority of the job row, in case it was updated after enqueue' do
        MyRetryJob.perform_later('RetryTestError')
        Delayed::Job.last.update!(priority: 5)

        expect(Delayed::Worker.new.work_off).to eq([1, 0])

        expect(Delayed::Job.last.priority).to eq(5)
      end
    end

    context 'when retry_on specifies a priority' do
      it 're-enqueues with the specified priority' do
        MyRetryJob.perform_later('RetryTestErrorWithSpecificPriority')

        expect(Delayed::Worker.new.work_off).to eq([1, 0])

        expect(Delayed::Job.last.priority).to eq(123)
      end
    end

    it 'records the error that triggered the retry on the re-enqueued job' do
      MyRetryJob.perform_later('RetryTestError')

      expect(Delayed::Worker.new.work_off).to eq([1, 0])

      expect(Delayed::Job.last.last_error).to start_with('RetryTestError')
    end

    it 'preserves the original creation time on the re-enqueued job' do
      Timecop.freeze(arbitrary_time) do
        MyRetryJob.perform_later('RetryTestError')
      end

      Timecop.freeze(arbitrary_time + 2.hours) do
        expect(Delayed::Worker.new.work_off).to eq([1, 0])
      end

      retried = Delayed::Job.last
      expect(retried.created_at).to eq(arbitrary_time)
      expect(retried.run_at).to be_within(1.second).of(arbitrary_time + 2.hours + 3.seconds)
    end

    context 'when attempts are exhausted' do
      it 're-raises the error, marking the ActiveJob as terminated and leaving the job to be retried by the worker itself' do
        job = MyRetryJob.new('RetryTestError')
        job.exception_executions = { '[RetryTestError]' => 4 } # retry_on defaults to 5 attempts
        job.enqueue
        original = Delayed::Job.last

        expect(Delayed::Worker.new.work_off).to eq([0, 1])

        expect(Delayed::Job.count).to eq(1)
        Delayed::Job.last.tap do |dj|
          expect(dj.id).to eq(original.id)
          expect(dj.attempts).to eq(1)
          expect(dj.last_error).to match(/RetryTestError/)
          expect(dj.payload_object.job_data['terminated_at']).to be_present
          expect(dj.payload_object.job_data['exception_executions']).to eq('[RetryTestError]' => 5)
        end
      end

      context 'when the worker then exhausts its own attempts and permanently fails the job' do
        before do
          Delayed::Worker.max_attempts = 1
        end

        it 'resets execution attempts if (and only if) the row attempts is set back to 0' do
          MyRetryJob.new('RetryTestError').tap do |job|
            job.executions = 4
            job.exception_executions = { '[RetryTestError]' => 4 }
            job.enqueue
          end

          expect(Delayed::Worker.new.work_off).to eq([0, 1])

          Delayed::Job.last.tap do |dj|
            expect(dj.failed_at).to be_present
            expect(dj.payload_object.job_data['terminated_at']).to be_present
            expect(dj.payload_object.job_data['executions']).to eq(4)
            expect(dj.payload_object.job_data['exception_executions']).to eq('[RetryTestError]' => 5)
          end

          # without setting attempts back to 0:
          Delayed::Job.last.update!(failed_at: nil, locked_at: nil, locked_by: nil)

          expect(Delayed::Worker.new.work_off).to eq([0, 1])

          retried = Delayed::Job.last
          expect(retried.failed_at).to be_present
          expect(retried.attempts).to eq(2)
          expect(retried.payload_object.job_data['terminated_at']).to be_present
          expect(retried.payload_object.job_data['executions']).to eq(4)
          expect(retried.payload_object.job_data['exception_executions']).to eq('[RetryTestError]' => 6)

          # also setting attempts back to 0:
          Delayed::Job.last.update!(failed_at: nil, attempts: 0, locked_at: nil, locked_by: nil)

          expect(Delayed::Worker.new.work_off).to eq([1, 0])

          retried = Delayed::Job.last
          expect(retried.failed_at).to be_nil
          expect(retried.attempts).to eq(0)
          expect(retried.payload_object.job_data['terminated_at']).to be_nil
          expect(retried.payload_object.job_data['executions']).to eq(1)
          expect(retried.payload_object.job_data['exception_executions']).to eq('[RetryTestError]' => 1)
        end
      end
    end

    if ActiveJob.gem_version.release >= Gem::Version.new('7.1')
      context 'when attempts is :unlimited' do
        let(:retry_job_class) do
          Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob
            retry_on(RetryTestError, attempts: :unlimited)

            queue_with_priority 567

            def perform(error_class_name)
              raise error_class_name.constantize
            end
          end
        end

        it 're-enqueues the job even when executions far exceed the default attempt limit' do
          job = MyRetryJob.new('RetryTestError')
          job.exception_executions = { '[RetryTestError]' => 10_000 }
          job.enqueue

          expect(Delayed::Worker.new.work_off).to eq([1, 0])

          retried = Delayed::Job.last
          expect(retried.payload_object.job_data['exception_executions']).to eq('[RetryTestError]' => 10_001)
        end
      end
    end

    context 'when using the ActiveJob test adapter' do
      let(:queue_adapter) { :test }

      it 're-enqueues with the priority specified by retry_on' do
        ActiveJob::Base.execute(MyRetryJob.new('RetryTestErrorWithSpecificPriority').serialize)

        expect(MyRetryJob.queue_adapter.enqueued_jobs.first).to include(job: MyRetryJob, 'priority' => 123)
      end

      it 're-enqueues with the original priority when retry_on does not specify one' do
        ActiveJob::Base.execute(MyRetryJob.new('RetryTestError').serialize)

        expect(MyRetryJob.queue_adapter.enqueued_jobs.first).to include(job: MyRetryJob, 'priority' => 567)
      end
    end
  end

  describe 'legacy job hooks' do
    let(:job_class) do
      Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob
        cattr_accessor(:messages) { [] }

        def perform
          self.class.messages << 'perform'
        end

        def before(_delayed_job)
          self.class.messages << 'before'
        end
      end
    end

    it 'invokes hooks defined on the job class, with a deprecation warning' do
      JobClass.perform_later
      delayed_job = enqueued_delayed_jobs.last

      expect { delayed_job.invoke_job }
        .to output(/\[DEPRECATION\] Job hook methods .* are deprecated\. Use ActiveJob callbacks instead\./).to_stderr

      expect(JobClass.messages).to eq(%w(before perform))
    end

    context 'when the job class does not define any hook methods' do
      let(:job_class) do
        Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob
          def perform; end
        end
      end

      it 'does not emit a deprecation warning' do
        JobClass.perform_later
        delayed_job = enqueued_delayed_jobs.last

        expect { delayed_job.invoke_job }.not_to output.to_stderr
      end
    end
  end

  describe '.enqueue_all' do # rubocop:disable Metrics/BlockLength
    let(:adapter) { ActiveJob::Base.queue_adapter }

    it 'returns 0 when given no jobs' do
      expect(adapter.enqueue_all([])).to eq(0)
    end

    it 'does not delegate to Delayed::Job.enqueue_all for empty input' do
      adapter.enqueue_all([])
      expect(enqueued_delayed_jobs).to be_empty
    end

    it 'delegates to Delayed::Job.enqueue_all with an Array<Delayed::Job>' do
      jobs = Array.new(3) { JobClass.new }
      adapter.enqueue_all(jobs)

      expect(Delayed::Job).to have_received(:enqueue_all).once
      expect(enqueued_delayed_jobs.size).to eq(3)
      expect(enqueued_delayed_jobs).to all(be_a(Delayed::Job))
    end

    it 'returns the count of jobs delegated' do
      jobs = Array.new(3) { JobClass.new }
      expect(adapter.enqueue_all(jobs)).to eq(3)
    end

    it 'honors per-job scheduled_at on the delegated Delayed::Job' do
      job = JobClass.new
      job.scheduled_at = arbitrary_time
      adapter.enqueue_all([JobClass.new, job])

      expect(enqueued_delayed_jobs[1].run_at).to eq(arbitrary_time)
    end

    it 'applies db_time_now to run_at when no scheduled_at is set' do
      Timecop.freeze(arbitrary_time) do
        adapter.enqueue_all([JobClass.new])
      end

      expect(enqueued_delayed_jobs.last.run_at).to eq(arbitrary_time)
    end

    it 'honors per-job queue and priority overrides on the delegated Delayed::Job' do
      a = JobClass.new.tap do |j|
        j.queue_name = 'q-a'
        j.priority = 3
      end
      b = JobClass.new.tap do |j|
        j.queue_name = 'q-b'
        j.priority = 7
      end

      adapter.enqueue_all([a, b])

      expect(enqueued_delayed_jobs[0]).to have_attributes(queue: 'q-a', priority: 3)
      expect(enqueued_delayed_jobs[1]).to have_attributes(queue: 'q-b', priority: 7)
    end

    it 'supports a mix of job classes in one call' do
      other_class = Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob
        def perform; end
      end
      stub_const('OtherJobClass', other_class)

      adapter.enqueue_all([JobClass.new, OtherJobClass.new])

      expect(enqueued_delayed_jobs.map(&:name)).to eq(%w(JobClass OtherJobClass))
    end

    it 'sets the name on the delegated Delayed::Job from display_name' do
      adapter.enqueue_all([JobClass.new])
      expect(enqueued_delayed_jobs.last.name).to eq('JobClass')
    end

    it 'copies the id from each delegated Delayed::Job onto the AJ input as provider_job_id' do
      skip 'requires INSERT ... RETURNING support' unless Delayed::Job.connection.supports_insert_returning?

      jobs = Array.new(3) { JobClass.new }
      adapter.enqueue_all(jobs)

      expect(jobs.map(&:provider_job_id)).to eq(enqueued_delayed_jobs.map(&:id))
      expect(jobs.map(&:provider_job_id)).to all(be_a(Integer))
    end

    if ActiveJob.gem_version.release >= Gem::Version.new('7.1')
      it 'marks each AJ input as successfully_enqueued' do
        jobs = Array.new(2) { JobClass.new }
        adapter.enqueue_all(jobs)
        expect(jobs).to all(be_successfully_enqueued)
      end
    end

    context 'when the database adapter does not support INSERT RETURNING (e.g. MySQL)' do
      before do
        allow(Delayed::Job.connection).to receive(:supports_insert_returning?).and_return(false)
      end

      it 'leaves provider_job_id nil on each AJ input' do
        jobs = Array.new(2) { JobClass.new }
        adapter.enqueue_all(jobs)
        expect(jobs.map(&:provider_job_id)).to all(be_nil)
      end
    end

    it 'does not fire ActiveJob before/around/after_enqueue callbacks' do
      fires = []
      JobClass.before_enqueue { fires << :before }
      JobClass.around_enqueue do |_j, block|
        fires << :around_before
        block.call
        fires << :around_after
      end
      JobClass.after_enqueue { fires << :after }

      adapter.enqueue_all([JobClass.new, JobClass.new])

      expect(fires).to be_empty
    end

    if ActiveJob.gem_version.release >= Gem::Version.new('7.2')
      context 'when a job sets enqueue_after_transaction_commit to :always' do
        before do
          JobClass.include ActiveJob::EnqueueAfterTransactionCommit
          JobClass.enqueue_after_transaction_commit = :always
        end

        it 'raises UnsafeEnqueueError and does not delegate to Delayed::Job.enqueue_all' do
          ActiveJob.deprecator.silence do
            expect { adapter.enqueue_all([JobClass.new]) }.to raise_error(Delayed::ActiveJobAdapter::UnsafeEnqueueError)
          end
          expect(enqueued_delayed_jobs).to be_empty
        end
      end
    end

    context 'when a job has a stale run_at and deny_stale_enqueues is enabled' do
      around do |example|
        was = Delayed::Worker.deny_stale_enqueues
        Delayed::Worker.deny_stale_enqueues = true
        example.run
      ensure
        Delayed::Worker.deny_stale_enqueues = was
      end

      it 'raises StaleEnqueueError and does not delegate to Delayed::Job.enqueue_all' do
        job = JobClass.new
        job.scheduled_at = Time.now.utc - 1.day
        expect { adapter.enqueue_all([JobClass.new, job]) }.to raise_error(Delayed::StaleEnqueueError)
        expect(enqueued_delayed_jobs).to be_empty
      end
    end
  end

  describe 'single-job perform_later routes through Delayed::Job.enqueue_all' do
    it 'invokes Delayed::Job.enqueue_all (not Delayed::Job.enqueue or Delayed::Job.enqueue_job)' do
      expect(Delayed::Job).not_to receive(:enqueue) # rubocop:disable RSpec/MessageSpies
      expect(Delayed::Job).not_to receive(:enqueue_job) # rubocop:disable RSpec/MessageSpies

      JobClass.perform_later

      expect(Delayed::Job).to have_received(:enqueue_all).once
    end

    it 'delegates exactly one Delayed::Job' do
      JobClass.perform_later
      expect(enqueued_delayed_jobs.size).to eq(1)
    end
  end

  if ActiveJob.gem_version.release >= Gem::Version.new('7.1')
    describe 'ActiveJob.perform_all_later' do
      it 'delegates all jobs to Delayed::Job.enqueue_all in a single call' do
        ActiveJob.perform_all_later([JobClass.new, JobClass.new, JobClass.new])

        expect(Delayed::Job).to have_received(:enqueue_all).once
        expect(enqueued_delayed_jobs.size).to eq(3)
      end

      it 'returns nil' do
        expect(ActiveJob.perform_all_later([JobClass.new])).to be_nil
      end
    end
  end
end
