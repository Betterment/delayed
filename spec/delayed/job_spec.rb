require 'helper'

describe Delayed::Job do
  let(:worker) { Delayed::Worker.new }

  def create_job(opts = {})
    described_class.create(opts.merge(payload_object: SimpleJob.new))
  end

  before do
    Delayed::Worker.max_priority = nil
    Delayed::Worker.min_priority = nil
    Delayed::Worker.max_claims = 1 # disable multithreading because SimpleJob is not threadsafe
    Delayed::Worker.default_priority = 99
    Delayed::Worker.delay_jobs = true
    Delayed::Worker.default_queue_name = 'default_tracking'
    SimpleJob.runs = 0
    described_class.delete_all
  end

  it 'sets run_at automatically if not set' do
    expect(described_class.create(payload_object: ErrorJob.new).run_at).not_to be_nil
  end

  it 'does not set run_at automatically if already set' do
    later = described_class.db_time_now + 5.minutes
    job = described_class.create(payload_object: ErrorJob.new, run_at: later)
    expect(job.run_at).to be_within(1).of(later)
  end

  describe '#reload' do
    it 'reloads the payload' do
      job = described_class.enqueue payload_object: SimpleJob.new
      expect(job.payload_object.object_id).not_to eq(job.reload.payload_object.object_id)
    end
  end

  describe 'enqueue' do
    it "allows enqueue hook to modify job at DB level" do
      later = described_class.db_time_now + 20.minutes
      job = described_class.enqueue payload_object: EnqueueJobMod.new
      expect(described_class.find(job.id).run_at).to be_within(1).of(later)
    end

    context 'with a hash' do
      it "raises ArgumentError when handler doesn't respond_to :perform" do
        expect { described_class.enqueue(payload_object: Object.new) }.to raise_error(ArgumentError)
      end

      it 'is able to set priority' do
        job = described_class.enqueue payload_object: SimpleJob.new, priority: 5
        expect(job.priority).to eq(5)
      end

      it 'is able to set priority by symbol name' do
        job = described_class.enqueue SimpleJob.new, priority: :eventual
        expect(job.priority).to be_eventual
        expect(job.priority).to eq(20)
      end

      it 'uses default priority' do
        job = described_class.enqueue payload_object: SimpleJob.new
        expect(job.priority).to eq(99)
      end

      it 'is able to set run_at' do
        later = described_class.db_time_now + 5.minutes
        job = described_class.enqueue payload_object: SimpleJob.new, run_at: later
        expect(job.run_at).to be_within(1).of(later)
      end

      it 'is able to set queue' do
        job = described_class.enqueue payload_object: NamedQueueJob.new, queue: 'tracking'
        expect(job.queue).to eq('tracking')
      end

      it 'uses default queue' do
        job = described_class.enqueue payload_object: SimpleJob.new
        expect(job.queue).to eq(Delayed::Worker.default_queue_name)
      end

      it "uses the payload object's queue" do
        job = described_class.enqueue payload_object: NamedQueueJob.new
        expect(job.queue).to eq(NamedQueueJob.new.queue_name)
      end
    end

    context 'with multiple arguments' do
      it "raises ArgumentError when handler doesn't respond_to :perform" do
        expect { described_class.enqueue(Object.new) }.to raise_error(ArgumentError)
      end

      it 'increases count after enqueuing items' do
        described_class.enqueue SimpleJob.new
        expect(described_class.count).to eq(1)
      end

      it 'uses default priority when it is not set' do
        @job = described_class.enqueue SimpleJob.new
        expect(@job.priority).to eq(99)
      end

      it 'works with jobs in modules' do
        M::ModuleJob.runs = 0
        job = described_class.enqueue M::ModuleJob.new
        expect { job.invoke_job }.to change { M::ModuleJob.runs }.from(0).to(1)
      end

      it 'does not mutate the options hash' do
        options = { priority: 1 }
        described_class.enqueue SimpleJob.new, options
        expect(options).to eq(priority: 1)
      end
    end

    context 'with delay_jobs = false' do
      before(:each) do
        Delayed::Worker.delay_jobs = false
      end

      it 'does not increase count after enqueuing items' do
        described_class.enqueue SimpleJob.new
        expect(described_class.count).to eq(0)
      end

      it 'invokes the enqueued job' do
        job = SimpleJob.new
        expect(job).to receive(:perform)
        described_class.enqueue job
      end

      it 'returns a job, not the result of invocation' do
        expect(described_class.enqueue(SimpleJob.new)).to be_instance_of(described_class)
      end
    end
  end

  describe 'callbacks' do
    before(:each) do
      CallbackJob.messages = []
    end

    %w(before success after).each do |callback|
      it "calls #{callback} with job" do
        job = described_class.enqueue(CallbackJob.new)
        expect(job.payload_object).to receive(callback).with(job)
        job.invoke_job
      end
    end

    it 'calls before and after callbacks' do
      job = described_class.enqueue(CallbackJob.new)
      expect(CallbackJob.messages).to eq(['enqueue'])
      job.invoke_job
      expect(CallbackJob.messages).to eq(%w(enqueue before perform success after))
    end

    it 'calls the after callback with an error' do
      job = described_class.enqueue(CallbackJob.new)
      expect(job.payload_object).to receive(:perform).and_raise(RuntimeError.new('fail'))

      expect { job.invoke_job }.to raise_error(RuntimeError, 'fail')
      expect(CallbackJob.messages).to eq(['enqueue', 'before', 'error: RuntimeError', 'after'])
    end

    it 'calls error when before raises an error' do
      job = described_class.enqueue(CallbackJob.new)
      expect(job.payload_object).to receive(:before).and_raise(RuntimeError.new('fail'))
      expect { job.invoke_job }.to raise_error(RuntimeError, 'fail')
      expect(CallbackJob.messages).to eq(['enqueue', 'error: RuntimeError', 'after'])
    end
  end

  describe 'payload_object' do
    it 'raises a DeserializationError when the job class is totally unknown' do
      job = described_class.new handler: '--- !ruby/object:JobThatDoesNotExist {}'
      expect { job.payload_object }.to raise_error(Delayed::DeserializationError)
    end

    it 'raises a DeserializationError when the job struct is totally unknown' do
      job = described_class.new handler: '--- !ruby/struct:StructThatDoesNotExist {}'
      expect { job.payload_object }.to raise_error(Delayed::DeserializationError)
    end

    it 'raises a DeserializationError when the YAML.load raises argument error' do
      job = described_class.new handler: '--- !ruby/struct:GoingToRaiseArgError {}'
      expect(YAML).to receive(:load_dj).and_raise(ArgumentError)
      expect { job.payload_object }.to raise_error(Delayed::DeserializationError)
    end

    it 'raises a DeserializationError when the YAML.load raises syntax error' do
      # only test with Psych since the other YAML parsers don't raise a SyntaxError
      unless /syck|yecht/i.match?(YAML.parser.class.name)
        job = described_class.new handler: 'message: "no ending quote'
        expect { job.payload_object }.to raise_error(Delayed::DeserializationError)
      end
    end
  end

  describe 'reserve' do
    before do
      Delayed::Worker.max_run_time = 2.minutes
    end

    after do
      Time.zone = nil
    end

    it 'does not reserve failed jobs' do
      create_job attempts: 50, failed_at: described_class.db_time_now
      expect(described_class.reserve(worker)).to eq []
    end

    it 'does not reserve jobs scheduled for the future' do
      create_job run_at: described_class.db_time_now + 1.minute
      expect(described_class.reserve(worker)).to eq []
    end

    it 'reserves jobs scheduled for the past' do
      job = create_job run_at: described_class.db_time_now - 1.minute
      expect(described_class.reserve(worker)).to eq([job])
    end

    it 'reserves jobs scheduled for the past when time zones are involved' do
      Time.zone = 'US/Eastern'
      job = create_job run_at: described_class.db_time_now - 1.minute
      expect(described_class.reserve(worker)).to eq([job])
    end

    it 'does not reserve jobs locked by other workers' do
      job = create_job
      other_worker = Delayed::Worker.new
      other_worker.name = 'other_worker'
      expect(described_class.reserve(other_worker)).to eq([job])
      expect(described_class.reserve(worker)).to eq []
    end

    it 'reserves open jobs' do
      job = create_job
      expect(described_class.reserve(worker)).to eq([job])
    end

    it 'reserves expired jobs' do
      job = create_job(locked_by: 'some other worker',
                       locked_at: described_class.db_time_now - Delayed::Worker.max_run_time - 1.minute)
      expect(described_class.reserve(worker)).to eq([job])
    end

    it 'reserves own jobs' do
      job = create_job(locked_by: worker.name, locked_at: (described_class.db_time_now - 1.minute))
      expect(described_class.reserve(worker)).to eq([job])
    end
  end

  describe '#name' do
    it 'is the class name of the job that was enqueued' do
      expect(described_class.create(payload_object: ErrorJob.new).name).to eq('ErrorJob')
    end

    it 'is the class name of the performable job if it is an ActiveJob' do
      job_wrapper = ActiveJob::QueueAdapters::DelayedJobAdapter::JobWrapper.new(ActiveJobJob.new.serialize)
      expect(described_class.create(payload_object: job_wrapper).name).to eq('ActiveJobJob')
    end

    it 'is the method that will be called if its a performable method object' do
      job = described_class.new(payload_object: NamedJob.new)
      expect(job.name).to eq('named_job')
    end

    it 'is the instance method that will be called if its a performable method object' do
      job = Story.create(text: '...').delay.save
      expect(job.name).to eq('Story#save')
    end

    it 'parses from handler on deserialization error' do
      job = Story.create(text: '...').delay.text
      job.payload_object.object.destroy
      expect(job.reload.name).to eq('Delayed::PerformableMethod')
    end
  end

  context 'worker prioritization' do
    after do
      Delayed::Worker.max_claims = nil
      Delayed::Worker.max_priority = nil
      Delayed::Worker.min_priority = nil
      Delayed::Worker.read_ahead = nil
    end

    it 'fetches jobs ordered by priority' do
      10.times { described_class.enqueue SimpleJob.new, priority: rand(10) }
      Delayed::Worker.read_ahead = 10
      Delayed::Worker.max_claims = 10
      jobs = described_class.reserve(worker)
      expect(jobs.size).to eq(10)
      jobs.each_cons(2) do |a, b|
        expect(a.priority).to be <= b.priority
      end
    end

    it 'only finds jobs greater than or equal to min priority' do
      min = 5
      Delayed::Worker.min_priority = min
      Delayed::Worker.max_claims = 2
      [4, 5, 6].sort_by { |_i| rand }.each { |i| create_job priority: i }
      jobs = described_class.reserve(worker)
      expect(jobs.map(&:priority).min).to be >= min
      jobs.map(&:destroy)
      expect(described_class.reserve(worker)).to eq []
    end

    it 'only finds jobs less than or equal to max priority' do
      max = 5
      Delayed::Worker.max_priority = max
      Delayed::Worker.max_claims = 2
      [4, 5, 6].sort_by { |_i| rand }.each { |i| create_job priority: i }
      jobs = described_class.reserve(worker)
      expect(jobs.map(&:priority).max).to be <= max
      jobs.map(&:destroy)
      expect(described_class.reserve(worker)).to eq []
    end
  end

  context 'clear_locks!' do
    before do
      @job = create_job(locked_by: 'worker1', locked_at: described_class.db_time_now)
    end

    it 'clears locks for the given worker' do
      described_class.clear_locks!('worker1')
      expect(described_class.reserve(worker)).to eq([@job])
    end

    it 'does not clear locks for other workers' do
      described_class.clear_locks!('different_worker')
      expect(described_class.reserve(worker)).not_to include(@job)
    end
  end

  context 'unlock' do
    before do
      @job = create_job(locked_by: 'worker', locked_at: described_class.db_time_now)
    end

    it 'clears locks' do
      @job.unlock
      expect(@job.locked_by).to be_nil
      expect(@job.locked_at).to be_nil
    end
  end

  context 'large handler' do
    before do
      text = 'Lorem ipsum dolor sit amet. ' * 1000
      @job = described_class.enqueue Delayed::PerformableMethod.new(text, :length, [], {})
    end

    it 'has an id' do
      expect(@job.id).not_to be_nil
    end
  end

  context 'named queues' do
    context 'when worker has one queue set' do
      before do
        Delayed::Worker.queues = ['large']
      end

      it 'only works off jobs which are from its queue' do
        expect(SimpleJob.runs).to eq(0)

        create_job(queue: 'large')
        create_job(queue: 'small')
        worker.work_off

        expect(SimpleJob.runs).to eq(1)
      end
    end

    context 'when worker has two queue set' do
      before do
        Delayed::Worker.queues = %w(large small)
      end

      it 'only works off jobs which are from its queue' do
        expect(SimpleJob.runs).to eq(0)

        create_job(queue: 'large')
        create_job(queue: 'small')
        create_job(queue: 'medium')
        create_job
        worker.work_off

        expect(SimpleJob.runs).to eq(2)
      end
    end

    context 'when worker does not have queue set' do
      before(:each) do
        Delayed::Worker.queues = []
      end

      it 'works off all jobs' do
        expect(SimpleJob.runs).to eq(0)

        create_job(queue: 'one')
        create_job(queue: 'two')
        create_job
        worker.work_off

        expect(SimpleJob.runs).to eq(3)
      end
    end
  end

  context 'max_attempts' do
    before(:each) do
      @job = described_class.enqueue SimpleJob.new
    end

    it 'is not defined' do
      expect(@job.max_attempts).to be_nil
    end

    it 'uses the max_attempts value on the payload when defined' do
      expect(@job.payload_object).to receive(:max_attempts).and_return(99)
      expect(@job.max_attempts).to eq(99)
    end
  end

  describe '#max_run_time' do
    before(:each) { @job = described_class.enqueue SimpleJob.new }

    it 'is not defined' do
      expect(@job.max_run_time).to be_nil
    end

    it 'results in a default run time when not defined' do
      expect(worker.max_run_time(@job)).to eq(20.minutes)
    end

    it 'uses the max_run_time value on the payload when defined' do
      expect(@job.payload_object).to receive(:max_run_time).and_return(10.minutes)
      expect(@job.max_run_time).to eq(10.minutes)
    end

    it 'results in an overridden run time when defined' do
      expect(@job.payload_object).to receive(:max_run_time).and_return(15.minutes)
      expect(worker.max_run_time(@job)).to eq(15.minutes)
    end

    it 'job set max_run_time can not exceed default max run time' do
      expect(@job.payload_object).to receive(:max_run_time).and_return(20.minutes + 60)
      expect(worker.max_run_time(@job)).to eq(20.minutes)
    end
  end

  describe 'destroy_failed_jobs' do
    context 'with a SimpleJob' do
      before(:each) do
        @job = described_class.enqueue SimpleJob.new
      end

      it 'is not defined' do
        expect(@job.destroy_failed_jobs?).to be false
      end

      it 'uses the destroy failed jobs value on the payload when defined' do
        expect(@job.payload_object).to receive(:destroy_failed_jobs?).and_return(true)
        expect(@job.destroy_failed_jobs?).to be true
      end
    end

    context 'with a job that raises DserializationError' do
      before(:each) do
        @job = described_class.new handler: '--- !ruby/struct:GoingToRaiseArgError {}'
      end

      it 'falls back reasonably' do
        expect(YAML).to receive(:load_dj).and_raise(ArgumentError)
        expect(@job.destroy_failed_jobs?).to be false
      end
    end
  end

  describe 'yaml serialization' do
    context 'when serializing jobs' do
      it 'raises error ArgumentError for new records' do
        story = Story.new(text: 'hello')
        if story.respond_to?(:new_record?)
          expect { story.delay.tell }.to raise_error(
            ArgumentError,
            "job cannot be created for non-persisted record: #{story.inspect}",
          )
        end
      end

      it 'raises error ArgumentError for destroyed records' do
        story = Story.create(text: 'hello')
        story.destroy
        expect { story.delay.tell }.to raise_error(
          ArgumentError,
          "job cannot be created for non-persisted record: #{story.inspect}",
        )
      end
    end

    context 'when reload jobs back' do
      it 'reloads changed attributes' do
        story = Story.create(text: 'hello')
        job = story.delay.tell
        story.text = 'goodbye'
        story.save!
        expect(job.reload.payload_object.object.text).to eq('goodbye')
      end

      it 'raises deserialization error for destroyed records' do
        story = Story.create(text: 'hello')
        job = story.delay.tell
        story.destroy
        expect { job.reload.payload_object }.to raise_error(Delayed::DeserializationError)
      end
    end
  end

  describe 'worker integration' do
    before do
      described_class.delete_all
      SimpleJob.runs = 0
    end

    describe 'running a job' do
      it 'fails after Worker.max_run_time' do
        Delayed::Worker.max_run_time = 1.second
        job = described_class.create payload_object: LongRunningJob.new
        worker.run(job)
        expect(job.error).not_to be_nil
        expect(job.reload.last_error).to match(/expired/)
        expect(job.reload.last_error).to match(/Delayed::Worker\.max_run_time is only 1 second/)
        expect(job.attempts).to eq(1)
      end

      context 'when the job raises a deserialization error' do
        it 'marks the job as failed' do
          job = described_class.create! handler: '--- !ruby/object:JobThatDoesNotExist {}'
          expect_any_instance_of(described_class).to receive(:destroy_failed_jobs?).and_return(false)
          worker.work_off
          job.reload
          expect(job).to be_failed
        end
      end
    end

    describe 'failed jobs' do
      before do
        @job = described_class.enqueue(ErrorJob.new, run_at: described_class.db_time_now - 1)
      end

      it 'records last_error when destroy_failed_jobs = false, max_attempts = 1' do
        Delayed::Worker.max_attempts = 1
        worker.run(@job)
        @job.reload
        expect(@job.error).not_to be_nil
        expect(@job.last_error).to match(/did not work/)
        expect(@job.attempts).to eq(1)
        expect(@job).to be_failed
      end

      it 're-schedules jobs after failing' do
        worker.work_off
        @job.reload
        expect(@job.last_error).to match(/did not work/)
        expect(@job.last_error).to match(/sample_jobs.rb:\d+:in `perform'/)
        expect(@job.attempts).to eq(1)
        expect(@job.run_at).to be > described_class.db_time_now - 10.minutes
        expect(@job.run_at).to be < described_class.db_time_now + 10.minutes
        expect(@job.locked_by).to be_nil
        expect(@job.locked_at).to be_nil
      end

      it 're-schedules jobs with handler provided time if present' do
        job = described_class.enqueue(CustomRescheduleJob.new(99.minutes))
        worker.run(job)
        job.reload

        expect((described_class.db_time_now + 99.minutes - job.run_at).abs).to be < 1
      end

      it "does not fail when the triggered error doesn't have a message" do
        error_with_nil_message = StandardError.new
        expect(error_with_nil_message).to receive(:message).twice.and_return(nil)
        expect(@job).to receive(:invoke_job).and_raise error_with_nil_message
        expect { worker.run(@job) }.not_to raise_error
      end
    end

    context 'reschedule' do
      before do
        @job = described_class.create payload_object: SimpleJob.new
      end

      shared_examples_for 'any failure more than Worker.max_attempts times' do
        context "when the job's payload has a #failure hook" do
          before do
            @job = described_class.create payload_object: OnPermanentFailureJob.new
            expect(@job.payload_object).to respond_to(:failure)
          end

          it 'runs that hook' do
            expect(@job.payload_object).to receive(:failure)
            worker.reschedule(@job)
          end

          it 'handles error in hook' do
            Delayed::Worker.destroy_failed_jobs = false
            @job.payload_object.raise_error = true
            expect { worker.reschedule(@job) }.not_to raise_error
            expect(@job.failed_at).not_to be_nil
          end
        end

        context "when the job's payload has no #failure hook" do
          # It's a little tricky to test this in a straightforward way,
          # because putting a not_to receive expectation on
          # @job.payload_object.failure makes that object incorrectly return
          # true to payload_object.respond_to? :failure, which is what
          # reschedule uses to decide whether to call failure. So instead, we
          # just make sure that the payload_object as it already stands doesn't
          # respond_to? failure, then shove it through the iterated reschedule
          # loop and make sure we don't get a NoMethodError (caused by calling
          # that nonexistent failure method).

          before do
            expect(@job.payload_object).not_to respond_to(:failure)
          end

          it 'does not try to run that hook' do
            expect {
              Delayed::Worker.max_attempts.times { worker.reschedule(@job) }
            }.not_to raise_exception
          end
        end
      end

      context 'and we want to destroy jobs' do
        before do
          Delayed::Worker.destroy_failed_jobs = true
        end

        it_behaves_like 'any failure more than Worker.max_attempts times'

        it 'is destroyed if it failed more than Worker.max_attempts times' do
          expect(@job).to receive(:destroy)
          Delayed::Worker.max_attempts.times { worker.reschedule(@job) }
        end

        it 'is destroyed if the job has destroy failed jobs set' do
          Delayed::Worker.destroy_failed_jobs = false
          expect(@job).to receive(:destroy_failed_jobs?).and_return(true)
          expect(@job).to receive(:destroy)
          Delayed::Worker.max_attempts.times { worker.reschedule(@job) }
        end

        it 'is not destroyed if failed fewer than Worker.max_attempts times' do
          expect(@job).not_to receive(:destroy)
          (Delayed::Worker.max_attempts - 1).times { worker.reschedule(@job) }
        end
      end

      context "and we don't want to destroy jobs" do
        it_behaves_like 'any failure more than Worker.max_attempts times'

        context 'and destroy failed jobs is false' do
          it 'is failed if it failed more than Worker.max_attempts times' do
            expect(@job.reload).not_to be_failed
            Delayed::Worker.max_attempts.times { worker.reschedule(@job) }
            expect(@job.reload).to be_failed
          end

          it 'is not failed if it failed fewer than Worker.max_attempts times' do
            (Delayed::Worker.max_attempts - 1).times { worker.reschedule(@job) }
            expect(@job.reload).not_to be_failed
          end
        end

        context 'and destroy failed jobs for job is false' do
          before do
            Delayed::Worker.destroy_failed_jobs = true
          end

          it 'is failed if it failed more than Worker.max_attempts times' do
            expect(@job).to receive(:destroy_failed_jobs?).and_return(false)
            expect(@job.reload).not_to be_failed
            Delayed::Worker.max_attempts.times { worker.reschedule(@job) }
            expect(@job.reload).to be_failed
          end

          it 'is not failed if it failed fewer than Worker.max_attempts times' do
            (Delayed::Worker.max_attempts - 1).times { worker.reschedule(@job) }
            expect(@job.reload).not_to be_failed
          end
        end
      end
    end
  end

  describe "reserve_with_scope" do
    let(:relation_class) { described_class.limit(1).class }
    let(:worker) { instance_double(Delayed::Worker, name: "worker01", read_ahead: 1, max_claims: 1) }
    let(:scope) do
      instance_double(relation_class, update_all: nil, limit: [job]).tap do |s|
        allow(s).to receive(:where).and_return(s)
      end
    end
    let(:job) { instance_double(described_class, id: 1, assign_attributes: true, changes_applied: true) }

    before do
      allow(described_class.connection).to receive(:adapter_name).at_least(:once).and_return(dbms)
    end

    context "for mysql adapters" do
      let(:dbms) { "MySQL" }

      it "uses the optimized sql version" do
        allow(described_class).to receive(:reserve_with_scope_using_default_sql)
        described_class.reserve_with_scope(scope, worker, Time.current)
        expect(described_class).not_to have_received(:reserve_with_scope_using_default_sql)
      end
    end

    context "for a dbms without a specific implementation" do
      let(:dbms) { "OtherDB" }

      it "uses the plain sql version" do
        allow(described_class).to receive(:reserve_with_scope_using_default_sql)
        described_class.reserve_with_scope(scope, worker, Time.current)
        expect(described_class).to have_received(:reserve_with_scope_using_default_sql).once
      end
    end
  end

  if ActiveRecord::VERSION::MAJOR >= 7
    delegate :default_timezone=, to: ActiveRecord
  else
    delegate :default_timezone=, to: ActiveRecord::Base
  end

  context "db_time_now" do
    after do
      Time.zone = nil
      self.default_timezone = :local
    end

    it "returns time in current time zone if set" do
      Time.zone = "Arizona"
      expect(described_class.db_time_now.zone).to eq("MST")
    end

    it "returns UTC time if that is the AR default" do
      Time.zone = nil
      self.default_timezone = :utc
      expect(described_class.db_time_now.zone).to eq "UTC"
    end

    it "returns local time if that is the AR default" do
      Time.zone = "Arizona"
      self.default_timezone = :local
      expect(described_class.db_time_now.zone).to eq("MST")
    end
  end

  context "ActiveRecord::Base.table_name_prefix" do
    it "when prefix is not set, use 'delayed_jobs' as table name" do
      ::ActiveRecord::Base.table_name_prefix = nil
      described_class.set_delayed_job_table_name

      expect(described_class.table_name).to eq "delayed_jobs"
    end

    it "when prefix is set, prepend it before default table name" do
      ::ActiveRecord::Base.table_name_prefix = "custom_"
      described_class.set_delayed_job_table_name

      expect(described_class.table_name).to eq "custom_delayed_jobs"

      ::ActiveRecord::Base.table_name_prefix = nil
      described_class.set_delayed_job_table_name
    end
  end

  describe '#age_alert?' do
    let(:now) { described_class.db_time_now }
    let(:run_at) { now - 1.minute }
    let(:locked_at) { nil }

    around do |example|
      Delayed::Priority.names = { high: 0 }
      Delayed::Priority.alerts = { high: { age: 5.minutes } }
      Timecop.freeze(now) { example.run }
    ensure
      Delayed::Priority.names = nil
    end

    subject { described_class.enqueue(SimpleJob.new, run_at: run_at, locked_at: locked_at) }

    it 'returns false' do
      expect(subject.alert_age).to eq(5.minutes)
      expect(subject.age).to be_within(1).of(1.minute)
      expect(subject.age_alert?).to eq(false)
    end

    context 'when the job is older than specified alert age' do
      let(:run_at) { now - 6.minutes }

      it 'returns true' do
        expect(subject.alert_age).to eq(5.minutes)
        expect(subject.age).to be_within(1).of(6.minutes)
        expect(subject.age_alert?).to eq(true)
      end
    end

    context 'when the job has been running for a long time but was picked up quickly' do
      let(:run_at) { now - 1.hour - 1.minute }
      let(:locked_at) { now - 1.hour }

      it 'returns false' do
        expect(subject.alert_age).to eq 5.minutes
        expect(subject.age).to be_within(1).of(1.minute)
        expect(subject.age_alert?).to eq(false)
      end
    end

    context 'when the job class defines an alert_age override' do
      before do
        stub_const('JobWithAlertAge', Struct.new(:perform) do
          def alert_age
            30.seconds
          end
        end)
      end

      subject { described_class.enqueue(JobWithAlertAge.new, run_at: run_at, locked_at: locked_at) }

      it 'obeys the override' do
        expect(subject.alert_age).to eq(30.seconds)
        expect(subject.age).to be_within(1).of(1.minute)
        expect(subject.age_alert?).to eq(true)
      end
    end
  end

  describe '#run_time_alert?' do
    let(:now) { described_class.db_time_now }
    let(:locked_at) { now - 1.minute }

    around do |example|
      Delayed::Priority.names = { high: 0 }
      Delayed::Priority.alerts = { high: { run_time: 5.minutes } }
      Timecop.freeze(now) { example.run }
    ensure
      Delayed::Priority.names = nil
    end

    subject { described_class.enqueue(SimpleJob.new, locked_at: locked_at) }

    it 'returns false' do
      expect(subject.alert_run_time).to eq(5.minutes)
      expect(subject.run_time).to be_within(1).of(1.minute)
      expect(subject.run_time_alert?).to eq(false)
    end

    context 'when the job is not locked (e.g. delay_jobs is false)' do
      let(:locked_at) { nil }

      it 'returns nil' do
        expect(subject.alert_run_time).to eq(5.minutes)
        expect(subject.run_time).to be_nil
        expect(subject.run_time_alert?).to be_nil
      end
    end

    context 'when the job has been running longer than specified alert run_time' do
      let(:locked_at) { now - 6.minutes }

      it 'returns true' do
        expect(subject.alert_run_time).to eq(5.minutes)
        expect(subject.run_time).to be_within(1).of(6.minutes)
        expect(subject.run_time_alert?).to eq(true)
      end
    end

    context 'when the job class defines an alert_run_time override' do
      before do
        stub_const('JobWithAlertRunTime', Struct.new(:perform) do
          def alert_run_time
            30.seconds
          end
        end)
      end

      subject { described_class.enqueue(JobWithAlertRunTime.new, locked_at: locked_at) }

      it 'obeys the override' do
        expect(subject.alert_run_time).to eq(30.seconds)
        expect(subject.run_time).to be_within(1).of(1.minute)
        expect(subject.run_time_alert?).to eq(true)
      end
    end
  end

  describe '#attempts_alert?' do
    let(:now) { described_class.db_time_now }
    let(:attempts) { 1 }

    around do |example|
      Delayed::Priority.names = { high: 0 }
      Delayed::Priority.alerts = { high: { attempts: 5 } }
      Timecop.freeze(now) { example.run }
    ensure
      Delayed::Priority.names = nil
    end

    subject { described_class.enqueue(SimpleJob.new, attempts: attempts) }

    it 'returns false' do
      expect(subject.alert_attempts).to eq 5
      expect(subject.attempts).to eq 1
      expect(subject.attempts_alert?).to eq false
    end

    context 'when the job reaches the specified alert attempts' do
      let(:attempts) { 6 }

      it 'returns true' do
        expect(subject.alert_attempts).to eq 5
        expect(subject.attempts).to eq 6
        expect(subject.attempts_alert?).to eq true
      end
    end

    context 'when the job class defines an alert_attempts override' do
      before do
        stub_const('JobWithAlertAttempts', Struct.new(:perform) do
          def alert_attempts
            1
          end
        end)
      end

      subject { described_class.enqueue(JobWithAlertAttempts.new, attempts: attempts) }

      it 'obeys the override' do
        expect(subject.alert_attempts).to eq 1
        expect(subject.attempts).to eq 1
        expect(subject.attempts_alert?).to eq true
      end
    end
  end
end
