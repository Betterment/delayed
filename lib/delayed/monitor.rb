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

    def self.sql_now_in_utc
      case ActiveRecord::Base.connection.adapter_name
      when 'PostgreSQL'
        "TIMEZONE('UTC', STATEMENT_TIMESTAMP())"
      when 'MySQL', 'Mysql2'
        "UTC_TIMESTAMP()"
      else
        "CURRENT_TIMESTAMP"
      end
    end

    def self.parse_utc_time(string)
      # Depending on Rails version & DB adapter, this will be either a String or a DateTime.
      # If it's a DateTime, and if connection is running with the `:local` time zone config,
      # then by default Rails incorrectly assumes it's in local time instead of UTC.
      # We use `strftime` to strip the encoded TZ info and re-parse it as UTC.
      #
      # Example:
      # - "2026-02-05 10:01:23"        -> DB-returned string
      # - "2026-02-05 10:01:23 -0600"  -> Rails-parsed DateTime with incorrect TZ
      # - "2026-02-05 10:01:23"        -> `strftime` output
      # - "2026-02-05 04:01:23 -0600"  -> Re-parsed as UTC and converted to local time
      string = string.strftime('%Y-%m-%d %H:%M:%S') if string.respond_to?(:strftime)

      ActiveSupport::TimeZone.new("UTC").parse(string)
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

    # This method generates a query that scans the specified scope, groups by
    # priority and queue, and calculates the specified aggregates. An outer
    # query is executed for priority bucketing and appending db_now_utc (to
    # avoid running these computations for each tuple in the inner query).
    def grouped_query(scope, include_db_time: false, **kwargs)
      inner_selects = kwargs.map { |key, (agg, expr)| as_expression(agg, expr, key) }
      outer_selects = kwargs.map { |key, (agg, _)| as_expression(agg == :count ? :sum : agg, key, key) }
      outer_selects << "#{self.class.sql_now_in_utc} AS db_now_utc" if include_db_time

      Delayed::Job
        .from(scope.select(:priority, :queue, *inner_selects).group(:priority, :queue))
        .group(priority_case_statement, :queue).select(
          *outer_selects,
          "#{priority_case_statement} AS priority",
          'queue AS queue',
        ).group_by { |j| [j.priority.to_i, j.queue] }
        .transform_values(&:first)
    end

    def as_expression(aggregate_function, aggregate_expression, column_name)
      "#{aggregate_function.to_s.upcase}(#{aggregate_expression}) AS #{column_name}"
    end

    def count_grouped
      failed_count_grouped.merge(live_count_grouped) { |_, l, f| l + f }
    end

    def live_count_grouped
      live_counts.transform_values(&:count)
    end

    def future_count_grouped
      live_counts.transform_values(&:future_count)
    end

    def erroring_count_grouped
      live_counts.transform_values(&:erroring_count)
    end

    def locked_count_grouped
      pending_counts.transform_values(&:claimed_count)
    end

    def failed_count_grouped
      failed_counts.transform_values(&:count)
    end

    def max_lock_age_grouped
      pending_counts.transform_values { |j| time_ago(db_now(j), j.locked_at) }
    end

    def max_age_grouped
      live_counts.transform_values { |j| time_ago(db_now(j), j.run_at) }
    end

    def alert_age_percent_grouped
      live_counts.each_with_object({}) do |((priority, queue), j), metrics|
        max_age = time_ago(db_now(j), j.run_at)
        alert_age = Priority.new(priority).alert_age
        metrics[[priority, queue]] = [max_age / alert_age * 100, 100].min if alert_age
      end
    end

    def workable_count_grouped
      pending_counts.transform_values(&:claimable_count)
    end

    alias working_count_grouped locked_count_grouped

    def oldest_locked_job_grouped
      pending_counts.transform_values(&:locked_at).compact
    end

    def oldest_workable_job_grouped
      live_counts.transform_values(&:run_at).compact
    end

    def live_counts
      @memo[:live_counts] ||= grouped_query(
        jobs.live,
        include_db_time: true,
        count: [:count, '*'],
        future_count: [:sum, case_when(Job.future_clause.to_sql)],
        erroring_count: [:sum, case_when(Job.erroring_clause.to_sql)],
        run_at: [:min, case_when(Job.pending_clause.to_sql, 'run_at')],
      )
    end

    def pending_counts
      @memo[:pending_counts] ||= grouped_query(
        jobs.pending,
        include_db_time: true,
        claimed_count: [:sum, case_when(Job.claimed_clause.to_sql)],
        claimable_count: [:sum, case_when(Job.claimable_clause.to_sql)],
        locked_at: [:min, case_when(Job.claimed_clause.to_sql, 'locked_at')],
      )
    end

    def failed_counts
      @memo[:failed_counts] ||= grouped_query(jobs.failed, count: [:count, '*'])
    end

    def db_now(record)
      self.class.parse_utc_time(record.db_now_utc)
    end

    def time_ago(now, value)
      [now - (value || now), 0].max
    end

    def case_when(condition, true_val = 1)
      "CASE WHEN #{condition} THEN #{true_val} ELSE #{true_val == 1 ? 0 : 'NULL'} END"
    end

    def priority_case_statement
      [
        'CASE',
        Priority.ranges.values.map do |range|
          if range.last.infinite?
            "WHEN priority >= #{range.first.to_i} THEN #{range.first.to_i}"
          else
            "WHEN priority < #{range.last.to_i} THEN #{range.first.to_i}"
          end
        end,
        'END',
      ].flatten.join(' ')
    end
  end
end
