module Delayed
  class Worker
    @@sleep_delay = 5
    
    cattr_accessor :sleep_delay

    cattr_accessor :logger
    self.logger = if defined?(Merb::Logger)
      Merb.logger
    elsif defined?(RAILS_DEFAULT_LOGGER)
      RAILS_DEFAULT_LOGGER
    end

    def job_max_run_time
      Delayed::Job.max_run_time
    end

    # Every worker has a unique name which by default is the pid of the process.
    # There are some advantages to overriding this with something which survives worker retarts:
    # Workers can safely resume working on tasks which are locked by themselves. The worker will assume that it crashed before.
    def name
      return @name unless @name.nil?
      "host:#{Socket.gethostname} pid:#{Process.pid}" rescue "pid:#{Process.pid}"
    end

    def name=(val)
      @name = val
    end

    def initialize(options={})
      @quiet = options[:quiet]
      Delayed::Job.min_priority = options[:min_priority] if options.has_key?(:min_priority)
      Delayed::Job.max_priority = options[:max_priority] if options.has_key?(:max_priority)
    end

    def start
      say "*** Starting job worker #{name}"

      trap('TERM') { say 'Exiting...'; $exit = true }
      trap('INT')  { say 'Exiting...'; $exit = true }

      loop do
        result = nil

        realtime = Benchmark.realtime do
          result = work_off
        end

        count = result.sum

        break if $exit

        if count.zero?
          sleep(@@sleep_delay)
        else
          say "#{count} jobs processed at %.4f j/s, %d failed ..." % [count / realtime, result.last]
        end

        break if $exit
      end

    ensure
      Delayed::Job.clear_locks!(name)
    end

    def say(text)
      puts text unless @quiet
      logger.info text if logger
    end

    protected

    # Run the next job we can get an exclusive lock on.
    # If no jobs are left we return nil
    def reserve_and_run_one_job(max_run_time = job_max_run_time)

      # We get up to 5 jobs from the db. In case we cannot get exclusive access to a job we try the next.
      # this leads to a more even distribution of jobs across the worker processes
      Delayed::Job.find_available(name, 5, max_run_time).each do |job|
        t = job.run_with_lock(max_run_time, name)
        return t unless t == nil  # return if we did work (good or bad)
      end

      nil # we didn't do any work, all 5 were not lockable
    end

    # Do num jobs and return stats on success/failure.
    # Exit early if interrupted.
    def work_off(num = 100)
      success, failure = 0, 0

      num.times do
        case reserve_and_run_one_job
        when true
            success += 1
        when false
            failure += 1
        else
          break  # leave if no work could be done
        end
        break if $exit # leave if we're exiting
      end

      return [success, failure]
    end
  end
end
