module Delayed
  class Monitor
    include Runnable

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
      alert_age_percent
    ).freeze

    cattr_accessor :sleep_delay, instance_writer: false, default: 60

    def initialize
      @jobs = Job.group(priority_case_statement).group(:queue)
      @jobs = @jobs.where(queue: Worker.queues) if Worker.queues.any?
    end

    def run!
      ActiveSupport::Notifications.instrument('delayed.monitor.run', default_tags) do
        METRICS.each { |metric| emit_metric!(metric) }
      end
      interruptable_sleep(sleep_delay)
    end

    private

    attr_reader :jobs

    def emit_metric!(metric)
      send("#{metric}_grouped").reverse_merge(default_results).each do |(priority, queue), value|
        ActiveSupport::Notifications.instrument(
          "delayed.job.#{metric}",
          default_tags.merge(priority: Priority.new(priority).to_s, queue: queue, value: value),
        )
      end
    end

    def default_results
      @default_results ||= Priority.names.values.flat_map { |priority|
        (Worker.queues.presence || [Worker.default_queue_name]).map do |queue|
          [[priority.to_i, queue], 0]
        end
      }.to_h
    end

    def say(message)
      Delayed.say(message)
    end

    def default_tags
      @default_tags ||= {
        table: Job.table_name,
        database: Job.database_name,
        database_adapter: Job.database_adapter_name,
      }
    end

    def count_grouped
      jobs.count
    end

    def future_count_grouped
      jobs.where("run_at > ?", Job.db_time_now).count
    end

    def locked_count_grouped
      jobs.locked.count
    end

    def erroring_count_grouped
      jobs.erroring.count
    end

    def failed_count_grouped
      jobs.failed.count
    end

    def max_lock_age_grouped
      oldest_locked_job_grouped.each_with_object({}) do |job, metrics|
        metrics[[job.priority.to_i, job.queue]] = Job.db_time_now - job.locked_at
      end
    end

    def max_age_grouped
      oldest_workable_job_grouped.each_with_object({}) do |job, metrics|
        metrics[[job.priority.to_i, job.queue]] = Job.db_time_now - job.run_at
      end
    end

    def alert_age_percent_grouped
      oldest_workable_job_grouped.each_with_object({}) do |job, metrics|
        max_age = Job.db_time_now - job.run_at
        metrics[[job.priority.to_i, job.queue]] = [max_age / job.priority.alert_age * 100, 100].min if job.priority.alert_age
      end
    end

    def workable_count_grouped
      jobs.workable(Job.db_time_now).count
    end

    def working_count_grouped
      jobs.working.count
    end

    def oldest_locked_job_grouped
      jobs.working.select("#{priority_case_statement} AS priority, queue, MIN(locked_at) AS locked_at")
    end

    def oldest_workable_job_grouped
      jobs.workable(Job.db_time_now).select("(#{priority_case_statement}) AS priority, queue, MIN(run_at) AS run_at")
    end

    def priority_case_statement
      [
        'CASE',
        Priority.ranges.values.map do |range|
          [
            "WHEN priority >= #{range.first.to_i}",
            ("AND priority < #{range.last.to_i}" unless range.last.infinite?),
            "THEN #{range.first.to_i}",
          ].compact
        end,
        'END',
      ].flatten.join(' ')
    end
  end
end
