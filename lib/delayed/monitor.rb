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
      @jobs = Job.group(:priority, :queue)
      @jobs = @jobs.where(queue: Worker.queues) if Worker.queues.any?
      @memo = {}
    end

    def run!
      @memo = {}
      ActiveSupport::Notifications.instrument('delayed.monitor.run', default_tags) do
        METRICS.each { |metric| emit_metric!(metric) }
      end
      interruptable_sleep(sleep_delay)
    end

    def query_for(metric)
      send(:"#{metric}_grouped")
    end

    private

    attr_reader :jobs

    def emit_metric!(metric)
      query_for(metric).reverse_merge(default_results).each do |(priority, queue), value|
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

    def grouped_count(scope)
      Delayed::Job.from(scope.select('priority, queue, COUNT(*) AS count'))
        .group(priority_case_statement, :queue).sum(:count)
    end

    def grouped_min(scope, column)
      Delayed::Job.from(scope.select("priority, queue, MIN(#{column}) AS #{column}"))
        .group(priority_case_statement, :queue).minimum(column)
    end

    def count_grouped
      if Job.connection.supports_partial_index?
        failed_count_grouped.merge(live_count_grouped) { |_, l, f| l + f }
      else
        grouped_count(jobs)
      end
    end

    def live_count_grouped
      grouped_count(jobs.live)
    end

    def future_count_grouped
      grouped_count(jobs.future)
    end

    def locked_count_grouped
      @memo[:locked_count_grouped] ||= grouped_count(jobs.claimed)
    end

    def erroring_count_grouped
      grouped_count(jobs.erroring)
    end

    def failed_count_grouped
      @memo[:failed_count_grouped] ||= grouped_count(jobs.failed)
    end

    def max_lock_age_grouped
      oldest_locked_job_grouped.transform_values { |locked_at| Job.db_time_now - locked_at }
    end

    def max_age_grouped
      oldest_workable_job_grouped.transform_values { |run_at| Job.db_time_now - run_at }
    end

    def alert_age_percent_grouped
      oldest_workable_job_grouped.each_with_object({}) do |((priority, queue), run_at), metrics|
        max_age = Job.db_time_now - run_at
        alert_age = Priority.new(priority).alert_age
        metrics[[priority, queue]] = [max_age / alert_age * 100, 100].min if alert_age
      end
    end

    def workable_count_grouped
      grouped_count(jobs.claimable)
    end

    alias working_count_grouped locked_count_grouped

    def oldest_locked_job_grouped
      grouped_min(jobs.claimed, :locked_at)
    end

    def oldest_workable_job_grouped
      @memo[:oldest_workable_job_grouped] ||= grouped_min(jobs.claimable, :run_at)
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
