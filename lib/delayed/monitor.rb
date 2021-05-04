module Delayed
  class Monitor
    METRICS = %w(
      count
      future_count
      locked_count
      erroring_count
      failed_count
      max_lock_age
      max_age
      working_count
      workable_count
    ).freeze

    DEFAULT_PRIORITIES = [0, 10, 20, 30].map { |i| [i, 0] }.to_h

    cattr_accessor(:sleep_interval) { 60 }

    def initialize
      @jobs = Job.group(:priority).where(priority: DEFAULT_PRIORITIES.keys)
      @as_of = Job.db_time_now
    end

    def start
      trap('TERM') { quit! }
      trap('INT') { quit! }

      say 'Starting job queue monitor'

      loop do
        emit!
        sleep(sleep_interval)
      end
    end

    def quit!
      Thread.new { say 'Exiting...' }.join
      exit # rubocop:disable Rails/Exit
    end

    def emit!
      METRICS.each do |metric|
        send("#{metric}_by_priority").reverse_merge(DEFAULT_PRIORITIES).each do |priority, value|
          ActiveSupport::Notifications.instrument(
            "delayed.job.#{metric}",
            default_tags.merge(priority: priority, value: value),
          )
        end
      end
    end

    private

    attr_reader :jobs, :as_of

    def say(message)
      Worker.logger.send(Worker.default_log_level, message)
    end

    def default_tags
      @default_tags ||= {
        table: Job.table_name,
        database: connection_config[:database],
        database_adapter: connection_config[:adapter],
      }
    end

    def connection_config
      Plugins::Instrumentation.connection_config(Job)
    end

    def count_by_priority
      jobs.count
    end

    def future_count_by_priority
      jobs.where("run_at > ?", as_of).count
    end

    def locked_count_by_priority
      jobs.claimed.count
    end

    def erroring_count_by_priority
      jobs.erroring.count
    end

    def failed_count_by_priority
      jobs.failed.count
    end

    def max_lock_age_by_priority
      oldest_locked_job_by_priority.each_with_object({}) do |job, metrics|
        metrics[job.priority] = as_of - job.locked_at
      end
    end

    def max_age_by_priority
      oldest_workable_job_by_priority.each_with_object({}) do |job, metrics|
        metrics[job.priority] = as_of - job.run_at
      end
    end

    def workable_count_by_priority
      jobs.workable(as_of).count
    end

    def working_count_by_priority
      jobs.working.count
    end

    def oldest_locked_job_by_priority
      jobs.working.select('priority, MIN(locked_at) AS locked_at')
    end

    def oldest_workable_job_by_priority
      jobs.workable(as_of).select('priority, MIN(run_at) AS run_at')
    end
  end
end
