# frozen_string_literal: true

module Delayed
  module Helpers
    module Migration
      def self.included(base)
        base.extend(ClassMethods)
        delegate :concurrent_index_creation_supported?, to: :class
      end

      module ClassMethods
        def concurrent_index_creation_supported?
          connection.index_algorithms.key?(:concurrently)
        end
      end

      def upsert_index(*args, **opts)
        dir(:both) { _drop_index_if_exists(*args) }
        dir(:up) { _add_index(*args, **opts) }
      end

      def remove_index_if_exists(*args, **opts)
        dir(:down) { _add_index(*args, **opts) }
        dir(:both) { _drop_index_if_exists(*args) }
      end

      def with_retry_loop(wait_timeout: 5.minutes, **opts)
        with_timeouts(**opts) do
          loop do
            yield
            break
          rescue ActiveRecord::LockWaitTimeout, ActiveRecord::StatementTimeout => e
            raise if Delayed::Job.db_time_now - @migration_start > wait_timeout

            Delayed.logger.warn("Index creation failed for #{opts[:name]}: #{e.message}. Retrying...")
          end
        end
      end

      def with_timeouts(statement_timeout: 1.minute, lock_timeout: 5.seconds)
        dir(:both) { set_timeouts!(statement_timeout: statement_timeout, lock_timeout: lock_timeout) }
        yield
      ensure
        dir(:both) { set_timeouts!(statement_timeout: nil, lock_timeout: nil) }
      end

      private

      def _add_index(*args, wait_timeout: nil, statement_timeout: nil, lock_timeout: nil, **opts)
        with_retry_loop(wait_timeout: wait_timeout, statement_timeout: statement_timeout, lock_timeout: lock_timeout) do
          add_index(*args, **opts)
        end
      end

      def _drop_index_if_exists(table, columns = nil, wait_timeout: nil, statement_timeout: nil, lock_timeout: nil)
        with_retry_loop(wait_timeout: wait_timeout, statement_timeout: statement_timeout, lock_timeout: lock_timeout) do
          remove_index(table, columns) if index_exists?(table, columns)
        end
      end

      def dir(direction, &block)
        reversible do |dir|
          dir.up(&block) if %i(up both).include?(direction)
          dir.down(&block) if %i(down both).include?(direction)
        end
      end

      def set_timeouts!(statement_timeout:, lock_timeout:)
        case connection.adapter_name
        when 'PostgreSQL'
          execute("SET statement_timeout TO #{pg_seconds(statement_timeout) || 'DEFAULT'};")
          execute("SET lock_timeout TO #{pg_seconds(lock_timeout) || 'DEFAULT'};")
        when 'MySQL', 'MariaDB'
          execute("SET SESSION wait_timeout = #{statement_timeout&.seconds || 'DEFAULT'};")
          execute("SET SESSION lock_wait_timeout = #{lock_timeout&.seconds || 'DEFAULT'};")
        else
          Delayed.logger.warn("[delayed] #{connection.adapter_name} does not support setting statement or lock timeouts (skipping).")
        end
      end

      def pg_seconds(duration)
        "'#{duration.seconds}s'" if duration
      end
    end
  end
end
