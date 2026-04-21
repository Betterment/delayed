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

    Delayed::Job.last.tap do |dj|
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

  it 'bubbles out an error if Delayed::Job.enqueue fails' do
    allow(Delayed::Job).to receive(:enqueue).and_raise("uh oh, enqueue failed!")

    expect { JobClass.perform_later }.to raise_error(RuntimeError, "uh oh, enqueue failed!")
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

  # `enqueue_all` / `perform_all_later` is an ActiveJob 7.1+ feature.
  if ActiveJob.gem_version.release >= Gem::Version.new('7.1') # rubocop:disable Metrics/BlockLength
    describe '.enqueue_all' do
      let(:adapter) { ActiveJob::Base.queue_adapter }

      it 'inserts multiple jobs in a single INSERT' do
        skip 'requires INSERT ... RETURNING support' unless Delayed::Job.connection.supports_insert_returning?

        jobs = Array.new(3) { JobClass.new }

        expect { adapter.enqueue_all(jobs) }
          .to emit_notification('sql.active_record').with_payload(hash_including(sql: a_string_matching(/\AINSERT INTO/i)))
        expect(Delayed::Job.count).to eq(3)
      end

      it 'returns the count of successfully enqueued jobs' do
        jobs = Array.new(3) { JobClass.new }
        expect(adapter.enqueue_all(jobs)).to eq(3)
      end

      it 'returns 0 when given no jobs' do
        expect(adapter.enqueue_all([])).to eq(0)
      end

      it 'sets provider_job_id on each input job' do
        jobs = Array.new(3) { JobClass.new }
        adapter.enqueue_all(jobs)
        expect(jobs.map(&:provider_job_id)).to match_array(Delayed::Job.pluck(:id))
      end

      it 'sets successfully_enqueued on each input job' do
        jobs = Array.new(2) { JobClass.new }
        adapter.enqueue_all(jobs)
        expect(jobs).to all(be_successfully_enqueued)
      end

      it 'honors per-job scheduled_at via .set(wait_until:)' do
        job = JobClass.new.set(wait_until: arbitrary_time)
        adapter.enqueue_all([JobClass.new, job])
        expect(Delayed::Job.find(job.provider_job_id).run_at).to eq(arbitrary_time)
      end

      it 'honors per-job scheduled_at via .set(wait:)' do
        Timecop.freeze(arbitrary_time) do
          job = JobClass.new.set(wait: 1.day)
          adapter.enqueue_all([job])
          expect(Delayed::Job.find(job.provider_job_id).run_at).to eq(arbitrary_time + 1.day)
        end
      end

      it 'applies db_time_now to run_at when no scheduled_at is set' do
        Timecop.freeze(arbitrary_time) do
          jobs = [JobClass.new]
          adapter.enqueue_all(jobs)
          expect(Delayed::Job.find(jobs.first.provider_job_id).run_at).to eq(arbitrary_time)
        end
      end

      it 'honors per-job queue and priority overrides' do
        a = JobClass.new.tap do |j|
          j.queue_name = 'q-a'
          j.priority = 3
        end
        b = JobClass.new.tap do |j|
          j.queue_name = 'q-b'
          j.priority = 7
        end

        adapter.enqueue_all([a, b])

        expect(Delayed::Job.find(a.provider_job_id)).to have_attributes(queue: 'q-a', priority: 3)
        expect(Delayed::Job.find(b.provider_job_id)).to have_attributes(queue: 'q-b', priority: 7)
      end

      it 'supports a mix of job classes in one call' do
        other_class = Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob
          def perform; end
        end
        stub_const('OtherJobClass', other_class)

        adapter.enqueue_all([JobClass.new, OtherJobClass.new])

        names = Delayed::Job.order(:id).pluck(:name)
        expect(names).to eq(%w(JobClass OtherJobClass))
      end

      it 'sets the name column from display_name' do
        adapter.enqueue_all([JobClass.new])
        expect(Delayed::Job.last.name).to eq('JobClass')
      end

      it "fires Delayed's :enqueue lifecycle callback for each job" do
        observed = []
        lifecycle_was = Delayed.lifecycle
        Delayed.instance_variable_set(:@lifecycle, Delayed::Lifecycle.new)
        Delayed.lifecycle.before(:enqueue) { |job| observed << job }

        adapter.enqueue_all([JobClass.new, JobClass.new, JobClass.new])

        expect(observed.size).to eq(3)
        expect(observed).to all(be_a(Delayed::Job))
      ensure
        Delayed.instance_variable_set(:@lifecycle, lifecycle_was)
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

          it 'raises UnsafeEnqueueError and inserts nothing' do
            ActiveJob.deprecator.silence do
              expect { adapter.enqueue_all([JobClass.new]) }.to raise_error(Delayed::ActiveJobAdapter::UnsafeEnqueueError)
            end
            expect(Delayed::Job.count).to eq(0)
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

        it 'raises StaleEnqueueError and inserts nothing' do
          job = JobClass.new.set(wait_until: Time.now.utc - 1.day)
          expect { adapter.enqueue_all([JobClass.new, job]) }.to raise_error(Delayed::StaleEnqueueError)
          expect(Delayed::Job.count).to eq(0)
        end
      end

      context 'when Delayed::Worker.delay_jobs is false' do
        around do |example|
          was = Delayed::Worker.delay_jobs
          Delayed::Worker.delay_jobs = false
          example.run
        ensure
          Delayed::Worker.delay_jobs = was
        end

        it 'invokes each job inline and inserts nothing' do
          job_class = Class.new(ActiveJob::Base) do # rubocop:disable Rails/ApplicationJob
            cattr_accessor(:runs) { 0 }
            def perform = self.class.runs += 1
          end
          stub_const('InlineJobClass', job_class)

          adapter.enqueue_all(Array.new(3) { InlineJobClass.new })

          expect(InlineJobClass.runs).to eq(3)
          expect(Delayed::Job.count).to eq(0)
        end
      end

      context 'when the database adapter does not support INSERT RETURNING (e.g. MySQL)' do
        before do
          allow(adapter).to receive(:bulk_enqueue_supported?).and_return(false)
        end

        it 'falls back to per-job enqueue and still populates provider_job_id' do
          jobs = Array.new(3) { JobClass.new }

          expect(adapter.enqueue_all(jobs)).to eq(3)
          expect(jobs).to all(be_successfully_enqueued)
          expect(jobs.map(&:provider_job_id)).to match_array(Delayed::Job.pluck(:id))
          expect(Delayed::Job.count).to eq(3)
        end
      end
    end

    describe 'ActiveJob.perform_all_later' do
      it 'bulk-enqueues all jobs with a single INSERT' do
        skip 'requires INSERT ... RETURNING support' unless Delayed::Job.connection.supports_insert_returning?

        expect { ActiveJob.perform_all_later([JobClass.new, JobClass.new, JobClass.new]) }
          .to emit_notification('sql.active_record').with_payload(hash_including(sql: a_string_matching(/\AINSERT INTO/i)))
        expect(Delayed::Job.count).to eq(3)
      end

      it 'returns nil' do
        expect(ActiveJob.perform_all_later([JobClass.new])).to be_nil
      end
    end
  end
end
