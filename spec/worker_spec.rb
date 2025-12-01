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

  describe '.max_run_time' do
    before { described_class.max_run_time = 1 }
    after { RescuesStandardErrorJob.runs = 0 }

    it 'times out and raises a WorkerTimeout that bypasses any StandardError rescuing' do
      Delayed::Job.enqueue RescuesStandardErrorJob.new
      described_class.new.work_off

      expect(Delayed::Job.count).to eq 1
      expect(RescuesStandardErrorJob.runs).to eq 1
      Delayed::Job.first.tap do |job|
        expect(job.attempts).to eq 1
        expect(job.last_error).to match(/execution expired/)
        expect(job.last_error).to match(/Delayed::Worker.max_run_time is only 1 second/)
      end
    end
  end

  describe 'lifecycle callbacks' do
    let(:plugin) do
      Class.new(Delayed::Plugin) do
        class << self
          attr_accessor :last_error, :raise_on

          def events
            @events ||= []
          end
        end

        callbacks do |lifecycle|
          lifecycle.around(:thread) do |_, &blk|
            events << :thread_start
            blk.call
            raise "oh no" if raise_on == :thread

            events << :thread_end
          end

          %i(perform error failure).each do |event|
            lifecycle.around(event) do |_, job, &blk|
              events << :"#{event}_start"
              raise "oh no" if raise_on == event

              blk.call.tap do
                self.last_error = job.last_error if event == :error
                events << :"#{event}_end"
              end
            end
          end
        end
      end
    end

    before do
      Delayed.plugins << plugin
    end

    it 'runs thread and perform callbacks' do
      Delayed::Job.enqueue SimpleJob.new
      described_class.new.work_off

      expect(plugin.events).to eq %i(thread_start perform_start perform_end thread_end)
      expect(plugin.last_error).to eq(nil)
      expect(Delayed::Job.count).to eq 0
    end

    context 'when thread callback raises an error' do
      before do
        plugin.raise_on = :thread
      end

      it 'logs that the thread crashed' do
        Delayed::Job.enqueue SimpleJob.new
        described_class.new.work_off

        expect(plugin.events).to eq %i(thread_start perform_start perform_end)
        expect(plugin.last_error).to eq(nil)
        expect(Delayed::Job.count).to eq 0
      end
    end

    context 'when the perform callback raises an error' do
      before do
        plugin.raise_on = :perform
      end

      it 'runs expected perform and error callbacks' do
        Delayed::Job.enqueue SimpleJob.new
        described_class.new.work_off

        expect(plugin.events).to eq %i(thread_start perform_start error_start error_end thread_end)
        expect(plugin.last_error).to match(/oh no/) # assert that cleanup happened before `:perform_end`
        expect(Delayed::Job.count).to eq 1
      end
    end

    context 'when the perform method raises an error' do
      it 'runs error callbacks' do
        Delayed::Job.enqueue ErrorJob.new
        described_class.new.work_off

        expect(plugin.events).to eq %i(thread_start perform_start error_start error_end thread_end)
        expect(plugin.last_error).to match(/did not work/) # assert that cleanup happened before `:perform_end`
        expect(Delayed::Job.count).to eq 1
      end

      context 'when error callback raises an error' do
        before do
          plugin.raise_on = :error
        end

        it 'runs thread and perform callbacks' do
          Delayed::Job.enqueue SimpleJob.new
          described_class.new.work_off

          expect(plugin.events).to eq %i(thread_start perform_start perform_end thread_end)
          expect(plugin.last_error).to eq(nil)
          expect(Delayed::Job.count).to eq 0
        end
      end
    end

    context 'when max attempts is exceeded' do
      it 'runs failure callbacks' do
        Delayed::Job.enqueue FailureJob.new
        described_class.new.work_off

        expect(plugin.events).to eq %i(thread_start perform_start error_start failure_start failure_end error_end thread_end)
        expect(plugin.last_error).to match(/did not work/) # assert that cleanup happened before `:perform_end`
        expect(Delayed::Job.count).to eq 1
      end

      context 'when failure callback raises an error' do
        before do
          plugin.raise_on = :failure
        end

        it 'runs thread and perform callbacks' do
          Delayed::Job.enqueue SimpleJob.new
          described_class.new.work_off

          expect(plugin.events).to eq %i(thread_start perform_start perform_end thread_end)
          expect(plugin.last_error).to eq(nil)
          expect(Delayed::Job.count).to eq 0
        end
      end
    end
  end
end
