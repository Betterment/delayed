require 'helper'

describe Delayed::Worker do
  describe 'start' do
    it 'runs the :execute lifecycle hook' do
      performances = []
      plugin = Class.new(Delayed::Plugin) do
        callbacks do |lifecycle|
          lifecycle.before(:execute) { performances << true }
          lifecycle.after(:execute) { |arg| performances << arg }
          lifecycle.around(:execute) { |arg, &block| performances << block.call(arg) }
        end
      end
      Delayed.plugins << plugin

      subject.send(:stop) # prevent start from running more than one loop
      allow(Delayed::Job).to receive(:reserve).and_return([])
      subject.start
      expect(performances).to eq [true, nil, nil]
      expect(Delayed::Job).to have_received(:reserve)
    end
  end

  # rubocop:disable RSpec/SubjectStub
  describe '#run!' do
    before do
      allow(Delayed.logger).to receive(:info).and_call_original
      allow(subject).to receive(:interruptable_sleep).and_call_original
    end

    around do |example|
      max_claims_was = described_class.max_claims
      described_class.max_claims = max_claims
      example.run
    ensure
      described_class.max_claims = max_claims_was
    end

    before do
      allow(Delayed::Job).to receive(:reserve).and_return((0...jobs_returned).map { job }, [])
    end

    let(:max_claims) { 1 }
    let(:jobs_returned) { 1 }
    let(:job) do
      instance_double(
        Delayed::Job,
        id: 123,
        max_run_time: 10,
        name: 'MyJob',
        run_at: Delayed::Job.db_time_now,
        created_at: Delayed::Job.db_time_now,
        priority: Delayed::Priority.interactive,
        queue: 'testqueue',
        attempts: 0,
        invoke_job: true,
        destroy: true,
      )
    end

    it 'logs the count and sleeps only within the loop' do
      subject.run!
      expect(Delayed.logger).to have_received(:info).with(/1 jobs processed/)
      expect(subject).to have_received(:interruptable_sleep).once.with(a_value_within(1).of(TEST_MIN_RESERVE_INTERVAL))
      expect(subject).not_to have_received(:interruptable_sleep).with(TEST_SLEEP_DELAY)
    end

    context 'when no jobs are returned' do
      let(:jobs_returned) { 0 }

      it 'does not log and then sleeps only outside of the loop' do
        subject.run!
        expect(Delayed.logger).not_to have_received(:info)
        expect(subject).to have_received(:interruptable_sleep).with(TEST_SLEEP_DELAY)
      end
    end

    context 'when max_claims is 3 and 3 jobs are returned' do
      let(:max_claims) { 3 }
      let(:jobs_returned) { 3 }

      it 'logs the count and sleeps only in the loop' do
        subject.run!
        expect(Delayed.logger).to have_received(:info).with(/3 jobs processed/)
        expect(subject).to have_received(:interruptable_sleep).once.with(a_value_within(1).of(TEST_MIN_RESERVE_INTERVAL))
        expect(subject).not_to have_received(:interruptable_sleep).with(TEST_SLEEP_DELAY)
      end
    end

    context 'when max_claims is 3 and 2 jobs are returned' do
      let(:max_claims) { 3 }
      let(:jobs_returned) { 2 }

      it 'logs the count and sleeps both in the loop and outside of the loop' do
        subject.run!
        expect(Delayed.logger).to have_received(:info).with(/2 jobs processed/)
        expect(subject).to have_received(:interruptable_sleep).once.with(a_value_within(1).of(TEST_MIN_RESERVE_INTERVAL))
        expect(subject).to have_received(:interruptable_sleep).once.with(TEST_SLEEP_DELAY)
      end
    end
  end
  # rubocop:enable RSpec/SubjectStub

  describe 'job_say' do
    before do
      @worker = described_class.new
      @job = double('job', id: 123, name: 'ExampleJob', queue: nil)
    end

    it 'logs with job name and id' do
      expect(@job).to receive(:queue)
      expect(@worker).to receive(:say)
        .with('Job ExampleJob (id=123) message', 'info')
      @worker.job_say(@job, 'message')
    end

    it 'logs with job name, queue and id' do
      expect(@job).to receive(:queue).and_return('test')
      expect(@worker).to receive(:say)
        .with('Job ExampleJob (id=123) (queue=test) message', 'info')
      @worker.job_say(@job, 'message')
    end

    it 'has a configurable default log level' do
      described_class.default_log_level = 'error'

      expect(@worker).to receive(:say)
        .with('Job ExampleJob (id=123) message', 'error')
      @worker.job_say(@job, 'message')
    ensure
      described_class.default_log_level = 'info'
    end
  end

  context 'worker read-ahead' do
    before do
      @read_ahead = described_class.read_ahead
    end

    after do
      described_class.read_ahead = @read_ahead
    end

    it 'reads five jobs' do
      expect(described_class.new.read_ahead).to eq(5)
    end

    it 'reads a configurable number of jobs' do
      described_class.read_ahead = 15
      expect(described_class.new.read_ahead).to eq(15)
    end
  end

  context 'worker job reservation' do
    it 'handles error during job reservation' do
      expect(Delayed::Job).to receive(:reserve).and_raise(Exception)
      described_class.new.work_off
    end

    it 'gives up after 10 backend failures' do
      expect(Delayed::Job).to receive(:reserve).exactly(10).times.and_raise(Exception)
      worker = described_class.new
      9.times { worker.work_off }
      expect { worker.work_off }.to raise_exception Delayed::FatalBackendError
    end

    it 'allows the backend to attempt recovery from reservation errors' do
      expect(Delayed::Job).to receive(:reserve).and_raise(Exception)
      expect(Delayed::Job).to receive(:recover_from).with(instance_of(Exception))
      described_class.new.work_off
    end
  end

  describe '#say' do
    before(:each) do
      @worker = described_class.new
      @worker.name = 'ExampleJob'
      time = Time.now
      allow(Time).to receive(:now).and_return(time)
      @text = 'Job executed'
      @worker_name = '[Worker(ExampleJob)]'
      @expected_time = time.strftime('%FT%T%z')
    end

    around do |example|
      logger = Delayed.logger
      Delayed.logger = double('job')
      example.run
    ensure
      Delayed.logger = logger
    end

    it 'logs a message on the default log level' do
      expect(Delayed.logger).to receive(:send)
        .with('info', "#{@expected_time}: #{@worker_name} #{@text}")
      @worker.say(@text)
    end

    it 'logs a message on a custom log level' do
      expect(Delayed.logger).to receive(:send)
        .with('error', "#{@expected_time}: #{@worker_name} #{@text}")
      @worker.say(@text, 'error')
    end
  end

  describe 'plugin registration' do
    it 'does not double-register plugins on worker instantiation' do
      performances = 0
      plugin = Class.new(Delayed::Plugin) do
        callbacks do |lifecycle|
          lifecycle.before(:enqueue) { performances += 1 }
        end
      end
      Delayed.plugins << plugin

      described_class.new
      described_class.new
      Delayed::Job.enqueue SimpleJob.new

      expect(performances).to eq(1)
    end
  end

  describe 'thread callback' do
    it 'wraps code after thread is checked out' do
      performances = Concurrent::AtomicFixnum.new(0)
      plugin = Class.new(Delayed::Plugin) do
        callbacks do |lifecycle|
          lifecycle.before(:thread) { performances.increment }
        end
      end
      Delayed.plugins << plugin

      Delayed::Job.delete_all
      Delayed::Job.enqueue SimpleJob.new
      worker = described_class.new

      worker.work_off

      expect(performances.value).to eq(1)
    end

    it 'wraps perform and cleanup, even when perform raises' do
      events = []
      last_error = nil

      plugin = Class.new(Delayed::Plugin) do
        callbacks do |lifecycle|
          lifecycle.around(:thread) do |_, &blk|
            events << :thread_start
            blk.call
            events << :thread_end
          end
          lifecycle.around(:perform) do |_, job, &blk|
            events << :perform_start
            blk.call.tap do
              last_error = job.last_error
              events << :perform_end
            end
          end
        end
      end

      Delayed.plugins << plugin

      Delayed::Job.enqueue ErrorJob.new
      described_class.new.work_off

      expect(events).to eq %i(thread_start perform_start perform_end thread_end)
      expect(last_error).to match(/did not work/) # assert that cleanup happened before `:perform_end`
    end
  end
end
