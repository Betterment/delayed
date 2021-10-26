module Delayed
  class Job < ::ActiveRecord::Base
    include Delayed::Backend::Base

    scope :by_priority, lambda { order("priority ASC, run_at ASC") }
    scope :min_priority, lambda { |priority| where("priority >= ?", priority) if priority }
    scope :max_priority, lambda { |priority| where("priority <= ?", priority) if priority }
    scope :for_queues, lambda { |queues| where(queue: queues) if queues.any? }

    scope :locked, -> { where.not(locked_at: nil) }
    scope :erroring, -> { where.not(last_error: nil) }
    scope :failed, -> { where.not(failed_at: nil) }
    scope :not_locked, -> { where(locked_at: nil) }
    scope :not_failed, -> { where(failed_at: nil) }
    scope :workable, ->(timestamp) { not_locked.not_failed.where("run_at <= ?", timestamp) }
    scope :working, -> { locked.not_failed }

    before_save :set_default_run_at

    REENQUEUE_BUFFER = 30.seconds

    def self.set_delayed_job_table_name
      delayed_job_table_name = "#{::ActiveRecord::Base.table_name_prefix}delayed_jobs"
      self.table_name = delayed_job_table_name
    end

    set_delayed_job_table_name

    def self.ready_to_run(worker_name, max_run_time)
      where(
        "((run_at <= ? AND (locked_at IS NULL OR locked_at < ?)) OR locked_by = ?) AND failed_at IS NULL",
        db_time_now,
        db_time_now - (max_run_time + REENQUEUE_BUFFER),
        worker_name,
      )
    end

    # When a worker is exiting, make sure we don't have any locked jobs.
    def self.clear_locks!(worker_name)
      where(locked_by: worker_name).update_all(locked_by: nil, locked_at: nil)
    end

    def self.reserve(worker, max_run_time = Worker.max_run_time)
      ready_scope =
        ready_to_run(worker.name, max_run_time)
          .min_priority(worker.min_priority)
          .max_priority(worker.max_priority)
          .for_queues(worker.queues)
          .by_priority

      ActiveSupport::Notifications.instrument('delayed.worker.reserve_jobs', worker_tags(worker)) do
        reserve_with_scope(ready_scope, worker, db_time_now)
      end
    end

    def self.reserve_with_scope(ready_scope, worker, now)
      case connection.adapter_name
        when "PostgreSQL", "PostGIS"
          reserve_with_scope_using_optimized_postgres(ready_scope, worker, now)
        when "MySQL", "Mysql2"
          reserve_with_scope_using_optimized_mysql(ready_scope, worker, now)
        when "MSSQL", "Teradata"
          reserve_with_scope_using_optimized_mssql(ready_scope, worker, now)
        # Fallback for unknown / other DBMS
        else
          reserve_with_scope_using_default_sql(ready_scope, worker, now)
      end
    end

    def self.reserve_with_scope_using_default_sql(ready_scope, worker, now)
      # This is our old fashion, tried and true, but possibly slower lookup
      # Instead of reading the entire job record for our detect loop, we select only the id,
      # and only read the full job record after we've successfully locked the job.
      # This can have a noticable impact on large read_ahead configurations and large payload jobs.
      attrs = { locked_at: now, locked_by: worker.name }

      jobs = []
      ready_scope.limit(worker.read_ahead).select(:id).each do |job|
        break if jobs.count >= worker.max_claims
        next unless ready_scope.where(id: job.id).update_all(attrs) == 1

        jobs << job.reload
      end

      jobs
    end

    def self.reserve_with_scope_using_optimized_postgres(ready_scope, worker, now) # rubocop:disable Metrics/AbcSize
      # Custom SQL required for PostgreSQL because postgres does not support UPDATE...LIMIT
      # This locks the single record 'FOR UPDATE' in the subquery
      # http://www.postgresql.org/docs/9.0/static/sql-select.html#SQL-FOR-UPDATE-SHARE
      # Note: active_record would attempt to generate UPDATE...LIMIT like
      # SQL for Postgres if we use a .limit() filter, but it would not
      # use 'FOR UPDATE' and we would have many locking conflicts
      table = connection.quote_table_name(table_name)

      # Rather than relying on a primary key, we use "WHERE ctid =", resulting in a fast 'Tid Scan'.
      if worker.max_claims > 1
        subquery = ready_scope.limit(worker.max_claims).lock("FOR UPDATE SKIP LOCKED").select("ctid").to_sql
        sql = "UPDATE #{table} SET locked_at = ?, locked_by = ? WHERE ctid = ANY (ARRAY (#{subquery})) RETURNING *"
      else
        subquery = ready_scope.limit(1).lock("FOR UPDATE SKIP LOCKED").select("ctid").to_sql
        sql = "UPDATE #{table} SET locked_at = ?, locked_by = ? WHERE ctid = (#{subquery}) RETURNING *"
      end

      find_by_sql([sql, now, worker.name]).sort_by(&:priority)
    end

    def self.reserve_with_scope_using_optimized_mysql(ready_scope, worker, now)
      # Removing the millisecond precision from now(time object)
      # MySQL 5.6.4 onwards millisecond precision exists, but the
      # datetime object created doesn't have precision, so discarded
      # while updating. But during the where clause, for mysql(>=5.6.4),
      # it queries with precision as well. So removing the precision
      now = now.change(usec: 0)
      # Despite MySQL's support of UPDATE...LIMIT, it has an optimizer bug
      # that results in filesorts rather than index scans, which is very
      # expensive with a large number of jobs in the table:
      # http://bugs.mysql.com/bug.php?id=74049
      # The PostgreSQL and MSSQL reserve strategies, while valid syntax in
      # MySQL, result in deadlocks so we use a SELECT then UPDATE strategy
      # that is more likely to false-negative when attempting to reserve
      # jobs in parallel but doesn't rely on subselects or transactions.

      # Also, we are fetching multiple candidate_jobs at a time to try to
      # avoid the situation where multiple workers try to grab the same
      # job at the same time. That previously had caused poor performance
      # since ready_scope.where(id: job.id) would return nothing even
      # though there was a large number of jobs on the queue.
      attrs = { locked_at: now, locked_by: worker.name }

      jobs = []
      ready_scope.limit(worker.read_ahead).each do |job|
        break if jobs.count >= worker.max_claims
        next unless ready_scope.where(id: job.id).update_all(attrs) == 1

        job.assign_attributes(attrs)
        job.send(:changes_applied)
        jobs << job
      end

      jobs
    end

    def self.reserve_with_scope_using_optimized_mssql(ready_scope, worker, now)
      # The MSSQL driver doesn't generate a limit clause when update_all
      # is called directly
      subsubquery_sql = ready_scope.limit(1).to_sql
      # select("id") doesn't generate a subquery, so force a subquery
      subquery_sql = "SELECT id FROM (#{subsubquery_sql}) AS x"
      quoted_table_name = connection.quote_table_name(table_name)
      sql = "UPDATE #{quoted_table_name} SET locked_at = ?, locked_by = ? WHERE id IN (#{subquery_sql})"
      count = connection.execute(sanitize_sql([sql, now, worker.name]))
      return [] if count.zero?

      # MSSQL JDBC doesn't support OUTPUT INSERTED.* for returning a result set, so query locked row
      where(locked_at: now, locked_by: worker.name, failed_at: nil)
    end

    # Get the current time (GMT or local depending on DB)
    # Note: This does not ping the DB to get the time, so all your clients
    # must have syncronized clocks.
    def self.db_time_now
      if Time.zone
        Time.zone.now
      elsif default_timezone == :utc
        Time.now.utc
      else
        Time.current
      end
    end

    if ActiveRecord::VERSION::MAJOR >= 7
      def self.default_timezone
        ActiveRecord.default_timezone
      end
    end

    def self.worker_tags(worker)
      {
        min_priority: worker.min_priority,
        max_priority: worker.max_priority,
        max_claims: worker.max_claims,
        read_ahead: worker.read_ahead,
        queues: worker.queues,
        table: table_name,
        database: database_name,
        database_adapter: database_adapter_name,
        worker: worker,
      }
    end

    def self.database_name
      connection_config[:database]
    end

    def self.database_adapter_name
      connection_config[:adapter]
    end

    if ActiveRecord.gem_version >= Gem::Version.new('6.1')
      def self.connection_config
        connection_db_config.configuration_hash
      end
    end

    def reload(*args)
      reset
      super
    end

    def alert_age
      if payload_object.respond_to?(:alert_age)
        payload_object.alert_age
      else
        priority.alert_age
      end
    end

    def alert_run_time
      if payload_object.respond_to?(:alert_run_time)
        payload_object.alert_run_time
      else
        priority.alert_run_time
      end
    end

    def alert_attempts
      if payload_object.respond_to?(:alert_attempts)
        payload_object.alert_attempts
      else
        priority.alert_attempts
      end
    end

    def age
      [(locked_at || self.class.db_time_now) - run_at, 0].max
    end

    def run_time
      self.class.db_time_now - locked_at if locked_at
    end

    def age_alert?
      alert_age&.<= age
    end

    def run_time_alert?
      alert_run_time&.<= run_time if run_time # locked_at may be `nil` if `delay_jobs` is false
    end

    def attempts_alert?
      alert_attempts&.<= attempts
    end
  end
end
