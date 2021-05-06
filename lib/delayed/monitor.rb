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

    cattr_accessor(:sleep_interval) { 60 }

    def initialize
      @jobs = Job.group(priority_case_statement).where(Job.arel_table[:priority].gteq(0))
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
        default_results = Priority.names.transform_keys(&:to_s).transform_values { |_| 0 }
        send("#{metric}_by_priority").reverse_merge(default_results).each do |priority, value|
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
        metrics[job.priority_name] = as_of - job.locked_at
      end
    end

    def max_age_by_priority
      oldest_workable_job_by_priority.each_with_object({}) do |job, metrics|
        metrics[job.priority_name] = as_of - job.run_at
      end
    end

    def workable_count_by_priority
      jobs.workable(as_of).count
    end

    def working_count_by_priority
      jobs.working.count
    end

    def oldest_locked_job_by_priority
      jobs.working.select("#{priority_case_statement} AS priority_name, MIN(locked_at) AS locked_at")
    end

    def oldest_workable_job_by_priority
      jobs.workable(as_of).select("#{priority_case_statement} AS priority_name, MIN(run_at) AS run_at")
    end

    def priority_case_statement
      [
        'CASE',
        Priority.ranges.map do |(name, range)|
          [
            "WHEN priority >= #{range.first.to_i}",
            ("AND priority < #{range.last.to_i}" unless range.last.infinite?),
            "THEN '#{name}'",
          ].compact
        end,
        'END',
      ].flatten.join(' ')
    end
  end
end
