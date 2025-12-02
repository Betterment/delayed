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

      def upsert_index(table, columns, wait_timeout: 5.minutes, statement_timeout: 1.minute, lock_timeout: 5.seconds, **opts)
        columns_or_name = opts.slice(:name).presence || columns

        with_timeouts(statement_timeout: statement_timeout, lock_timeout: lock_timeout) do
          loop do
            reversible do |dir|
              dir.up do
                remove_index(table, columns_or_name) if index_exists?(table, columns_or_name)
                add_index(table, columns, **opts)
              end
              dir.down { remove_index(table, columns_or_name) }
            end

            break
          rescue ActiveRecord::LockWaitTimeout, ActiveRecord::StatementTimeout => e
            raise if Delayed::Job.db_time_now - @migration_start > wait_timeout

            Delayed.logger.warn("Index creation failed for #{opts[:name]}: #{e.message}. Retrying...")
          end
        end
      end

      def with_timeouts(statement_timeout:, lock_timeout:)
        both_dirs { set_timeouts!(statement_timeout: statement_timeout, lock_timeout: lock_timeout) }
        yield
      ensure
        both_dirs { set_timeouts!(statement_timeout: nil, lock_timeout: nil) }
      end

      private

      def both_dirs(&block)
        reversible do |dir|
          dir.up(&block)
          dir.down(&block)
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
