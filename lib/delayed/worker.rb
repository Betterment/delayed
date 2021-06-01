require 'timeout'
require 'active_support/dependencies'
require 'active_support/core_ext/numeric/time'
require 'active_support/core_ext/class/attribute_accessors'
require 'active_support/hash_with_indifferent_access'
require 'active_support/core_ext/hash/indifferent_access'
require 'benchmark'
require 'concurrent'

module Delayed
  class Worker
    include Runnable

    DEFAULT_SLEEP_DELAY      = 5
    DEFAULT_MAX_ATTEMPTS     = 25
    DEFAULT_MAX_CLAIMS       = 2
    DEFAULT_MAX_RUN_TIME     = 4.hours
    DEFAULT_DEFAULT_PRIORITY = 0
    DEFAULT_DELAY_JOBS       = true
    DEFAULT_QUEUES           = [].freeze
    DEFAULT_READ_AHEAD       = 5

    cattr_accessor :min_priority, :max_priority, :max_attempts, :max_run_time,
                   :default_priority, :sleep_delay, :delay_jobs, :queues,
                   :read_ahead, :destroy_failed_jobs, :max_claims

    # Named queue into which jobs are enqueued by default
    cattr_accessor :default_queue_name

    # name_prefix is ignored if name is set directly
    attr_accessor :name_prefix

    class << self
      delegate :lifecycle, :plugins, :plugins=, :logger, :logger=,
               :default_log_level, :default_log_level=, to: Delayed
    end

    def self.reset
      self.sleep_delay       = DEFAULT_SLEEP_DELAY
      self.max_attempts      = DEFAULT_MAX_ATTEMPTS
      self.max_claims        = DEFAULT_MAX_CLAIMS
      self.max_run_time      = DEFAULT_MAX_RUN_TIME
      self.default_priority  = DEFAULT_DEFAULT_PRIORITY
      self.delay_jobs        = DEFAULT_DELAY_JOBS
      self.queues            = DEFAULT_QUEUES
      self.read_ahead        = DEFAULT_READ_AHEAD
    end

    # By default failed jobs are not destroyed. This means you must monitor for them
    # and have a process for addressing them, or your table will continually expand.
    self.destroy_failed_jobs = false

    def self.reload_app?
      defined?(ActionDispatch::Reloader) && Rails.application.config.cache_classes == false
    end

    def self.delay_job?(job)
      if delay_jobs.is_a?(Proc)
        delay_jobs.arity == 1 ? delay_jobs.call(job) : delay_jobs.call
      else
        delay_jobs
      end
    end

    def initialize(options = {})
      @failed_reserve_count = 0

      %i(min_priority max_claims max_priority sleep_delay read_ahead queues).each do |option|
        self.class.send("#{option}=", options[option]) if options.key?(option)
      end

      # Reset lifecycle on the offhand chance that something lazily
      # triggered its creation before all plugins had been registered.
      Delayed.setup_lifecycle
    end

    # Every worker has a unique name which by default is the pid of the process. There are some
    # advantages to overriding this with something which survives worker restarts:  Workers can
    # safely resume working on tasks which are locked by themselves. The worker will assume that
    # it crashed before.
    def name
      return @name unless @name.nil?

      begin
        "#{@name_prefix}host:#{Socket.gethostname} pid:#{Process.pid}"
      rescue StandardError
        "#{@name_prefix}pid:#{Process.pid}"
      end
    end

    # Sets the name of the worker.
    # Setting the name to nil will reset the default worker name
    attr_writer :name

    def run!
      @realtime = Benchmark.realtime do
        @result = work_off
      end

      count = @result[0] + @result[1]

      say format("#{count} jobs processed at %.4f j/s, %d failed", count / @realtime, @result.last) if count.positive?
      interruptable_sleep(self.class.sleep_delay) if count < max_claims

      reload! unless stop?
    end

    def on_exit!
      Delayed::Job.clear_locks!(name)
    end

    # Do num jobs and return stats on success/failure.
    # Exit early if interrupted.
    def work_off(num = 100)
      success = Concurrent::AtomicFixnum.new(0)
      failure = Concurrent::AtomicFixnum.new(0)

      num.times do
        jobs = reserve_jobs
        break if jobs.empty?

        pool = Concurrent::FixedThreadPool.new(jobs.length)
        jobs.each do |job|
          pool.post do
            run_thread_callbacks(job) do
              if run_job(job)
                success.increment
              else
                failure.increment
              end
            end
          end
        end

        pool.shutdown
        pool.wait_for_termination

        break if stop? # leave if we're exiting
      end

      [success, failure].map(&:value)
    end

    def run_thread_callbacks(job, &block)
      self.class.lifecycle.run_callbacks(:thread, self, job, &block)
    end

    def run(job)
      metadata = {
        status: 'RUNNING',
        name: job.name,
        run_at: job.run_at,
        created_at: job.created_at,
        priority: job.priority,
        queue: job.queue,
        attempts: job.attempts,
        enqueued_for: (Time.current - job.created_at).round,
      }
      job_say job, metadata.to_json
      runtime = Benchmark.realtime do
        Timeout.timeout(max_run_time(job).to_i, WorkerTimeout) do
          job.invoke_job
        end
        job.destroy
      end
      job_say job, format('COMPLETED after %.4f seconds', runtime)
      true # did work
    rescue DeserializationError => e
      job_say job, "FAILED permanently with #{e.class.name}: #{e.message}", 'error'

      job.error = e
      failed(job)
    rescue Exception => e # rubocop:disable Lint/RescueException
      self.class.lifecycle.run_callbacks(:error, self, job) { handle_failed_job(job, e) }
      false # work failed
    end

    # Reschedule the job in the future (when a job fails).
    # Uses an exponential scale depending on the number of failed attempts.
    def reschedule(job, time = nil)
      if (job.attempts += 1) < max_attempts(job)
        time ||= job.reschedule_at
        job.run_at = time
        job.unlock
        job.save!
      else
        job_say job, "FAILED permanently because of #{job.attempts} consecutive failures", 'error'
        failed(job)
      end
    end

    def failed(job)
      self.class.lifecycle.run_callbacks(:failure, self, job) do
        job.hook(:failure)
      rescue StandardError => e
        say "Error when running failure callback: #{e}", 'error'
        say e.backtrace.join("\n"), 'error'
      ensure
        job.destroy_failed_jobs? ? job.destroy : job.fail!
      end
    end

    def job_say(job, text, level = Delayed.default_log_level)
      text = "Job #{job.name} (id=#{job.id})#{say_queue(job.queue)} #{text}"
      say text, level
    end

    def say(text, level = Delayed.default_log_level)
      text = "[Worker(#{name})] #{text}"
      Delayed.say("#{Time.now.strftime('%FT%T%z')}: #{text}", level)
    end

    def max_attempts(job)
      job.max_attempts || self.class.max_attempts
    end

    def max_run_time(job)
      job.max_run_time || self.class.max_run_time
    end

    protected

    def say_queue(queue)
      " (queue=#{queue})" if queue
    end

    def handle_failed_job(job, error)
      job.error = error
      job_say job, "FAILED (#{job.attempts} prior attempts) with #{error.class.name}: #{error.message}", 'error'
      reschedule(job)
    end

    def run_job(job)
      self.class.lifecycle.run_callbacks(:perform, self, job) { run(job) }
    end

    # The backend adapter may return either a list or a single job
    # In some backends, this can be controlled with the `max_claims` config
    # Either way, we map this to an array of job instances
    def reserve_jobs
      jobs = [Delayed::Job.reserve(self)].compact.flatten(1)
      @failed_reserve_count = 0
      jobs
    rescue ::Exception => e # rubocop:disable Lint/RescueException
      say "Error while reserving job(s): #{e}"
      Delayed::Job.recover_from(e)
      @failed_reserve_count += 1
      raise FatalBackendError if @failed_reserve_count >= 10

      []
    end

    def reload!
      return unless self.class.reload_app?

      if defined?(ActiveSupport::Reloader)
        Rails.application.reloader.reload!
      else
        ActionDispatch::Reloader.cleanup!
        ActionDispatch::Reloader.prepare!
      end
    end
  end
end

Delayed::Worker.reset
