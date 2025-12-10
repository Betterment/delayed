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
        dir(:up) { _add_or_replace_index(*args, **opts) }
        dir(:down) { _drop_index_if_exists(*args, **opts) }
      end

      def remove_index_if_exists(*args, **opts)
        dir(:up) { _drop_index_if_exists(*args, **opts) }
        dir(:down) { _add_or_replace_index(*args, **opts) }
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

      def _add_or_replace_index(table, columns, **opts)
        index = _lookup_index(table, columns, **opts)
        if index && !_index_matches?(index, **opts)
          Delayed.logger.warn("Recreating index #{index.name} (is invalid or does not match desired options)")
          _drop_index(table, name: index.name, **opts)
        end
        _add_index(table, columns, **opts) if !index || !_index_matches?(index, **opts)
      end

      def _drop_index_if_exists(table, columns, **opts)
        index = _lookup_index(table, columns, **opts)
        _drop_index(table, name: index.name, **opts) if index
      end

      def _add_index(*args, **opts)
        index_opts = opts.slice!(:wait_timeout, :statement_timeout, :lock_timeout)
        with_retry_loop(**opts) { add_index(*args, **index_opts) }
      end

      def _drop_index(table, name:, **opts)
        opts.slice!(:wait_timeout, :statement_timeout, :lock_timeout)
        with_retry_loop(**opts) { remove_index(table, name: name) }
      end

      def _lookup_index(table, columns, **opts)
        connection.indexes(table).find { |idx| idx.name == opts[:name] || idx.columns == Array(columns).map(&:to_s) }
      end

      def _index_matches?(index, **opts)
        using_default = :btree unless connection.adapter_name == 'SQLite'

        { unique: false, where: nil, using: using_default, include: nil, valid?: true }.all? do |key, default|
          !index.respond_to?(key) || opts.fetch(key, default) == index.public_send(key)
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
