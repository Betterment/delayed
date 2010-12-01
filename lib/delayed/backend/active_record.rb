require 'active_record'

module Delayed
  module Backend
    module ActiveRecord
      # A job object that is persisted to the database.
      # Contains the work object as a YAML field.
      class Job < ::ActiveRecord::Base
        include Delayed::Backend::Base
        set_table_name :delayed_jobs

        before_save :set_default_run_at

        scope :ready_to_run, lambda {|worker_name, max_run_time|
          where(['(run_at <= ? AND (locked_at IS NULL OR locked_at < ?) OR locked_by = ?) AND failed_at IS NULL', db_time_now, db_time_now - max_run_time, worker_name])
        }
        scope :by_priority, order('priority ASC, run_at ASC')

        scope :locked_by_worker, lambda{|worker_name, max_run_time|
          where(['locked_by = ? AND locked_at > ?', worker_name, db_time_now - max_run_time])
        }

        def self.before_fork
          ::ActiveRecord::Base.clear_all_connections!
        end

        def self.after_fork
          ::ActiveRecord::Base.establish_connection
        end

        # When a worker is exiting, make sure we don't have any locked jobs.
        def self.clear_locks!(worker_name)
          update_all("locked_by = null, locked_at = null", ["locked_by = ?", worker_name])
        end

        def self.jobs_available_to_worker(worker_name, max_run_time)
          scope = self.ready_to_run(worker_name, max_run_time)
          scope = scope.scoped(:conditions => ['priority >= ?', Worker.min_priority]) if Worker.min_priority
          scope = scope.scoped(:conditions => ['priority <= ?', Worker.max_priority]) if Worker.max_priority
          scope.by_priority
        end

        # Reserve a single job in a single update query.  This causes workers to serialize on the
        # database and avoids contention.
        def self.reserve(worker, max_run_time = Worker.max_run_time)
          affected_rows = 0
          ::ActiveRecord::Base.silence do
            affected_rows = jobs_available_to_worker(worker.name, max_run_time).limit(1).update_all(["locked_at = ?, locked_by = ?", db_time_now, worker.name])
          end

          if affected_rows == 1
            locked_by_worker(worker.name, max_run_time).first
          else
            nil
          end
        end

        # Get the current time (GMT or local depending on DB)
        # Note: This does not ping the DB to get the time, so all your clients
        # must have syncronized clocks.
        def self.db_time_now
          if Time.zone
            Time.zone.now
          elsif ::ActiveRecord::Base.default_timezone == :utc
            Time.now.utc
          else
            Time.now
          end
        end

      end
    end
  end
end
