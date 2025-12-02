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
        set_timeouts!(statement_timeout: statement_timeout, lock_timeout: lock_timeout)

        loop do
          begin
            remove_index(table, name: opts[:name]) if index_exists?(table, columns, name: opts[:name])

            reversible do |direction|
              direction.up { add_index(table, columns, **opts) }
            end

            break
          rescue StandardError => e
            Delayed.logger.warn("Index creation failed for #{opts[:name]}: #{e.message}. Retrying...")
          end

          break if Delayed::Job.db_time_now - @migration_start > wait_timeout
        end
      ensure
        set_timeouts!(statement_timeout: nil, lock_timeout: nil)
      end

      private

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
