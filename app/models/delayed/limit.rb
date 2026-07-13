# frozen_string_literal: true

module Delayed
  # A database-backed concurrency limiter/optimizer designed for use with
  # `Delayed::Job`. Given a 'purpose' (stringy identifier), a limit, and a time
  # interval, it will attempt to maximize throughput without exceeding the limit
  # ("traffic shaping"). The `wait_timeout` parameter can also be lowered (from
  # its default of `5.seconds`) in order to shed load more proactively ("traffic
  # enforcement").
  #
  # Because the algorithm relies on database-specific timestamp arithmetic and
  # an upserting `RETURNING` clause, only PostgreSQL and SQLite (3.35+) are
  # supported. (See `.supported?`.)
  #
  # Wrap the work you want to limit in a block, and the limiter will either
  # yield to the block (within the configured `wait_timeout`) or raise
  # `LimitExceededError` immediately (if the `wait_timeout` would be exceeded):
  #
  #   Delayed::Limit.within_limit(:emails, max: 100, per: 1.minute) do
  #     deliver_email!
  #   end
  #
  # Currently, the limiter does not support "burst" capacity. A limit of 60
  # req/minute will behave identically to a limit of 1 req/second, because the
  # limiter only allows a single call per "drain interval" (`per / max`). When
  # combined with the `wait_timeout`, this degree of smoothing is acceptable for
  # background job processing (and traffic shaping in general), but may be
  # revisited in the future to support more types of workloads.
  #
  # To share a limit across multiple calls, register a named 'purpose' in
  # advance (e.g. in an initializer) and then reference it by name later:
  #
  #   Delayed::Limit.register!(:emails, max: 100, per: 1.minute)
  #
  #   Delayed::Limit.within_limit(:emails, wait_timeout: 10.seconds) do
  #     deliver_email!
  #   end
  #
  # It is **not** recommended to register limits dynamically at runtime, because
  # registered limits are cached indefinitely in memory and are not thread-safe.
  class Limit < ActiveRecord::Base
    self.table_name = 'delayed_limits'

    # SQLite gained support for the `RETURNING` clause in version 3.35.
    MINIMUM_SQLITE_VERSION = Gem::Version.new('3.35.0')
    SECONDS_PER_DAY = 86_400.0

    # Raised when limit adherence would require exceeding the `wait_timeout`.
    class LimitExceededError < StandardError; end

    class << self
      # Used only for limits registered in advance (via `.register!`):
      def limits
        @limits ||= {}.freeze
      end

      # The algorithm requires an upserting `RETURNING` clause and timestamp
      # arithmetic, so only certain database adapters/versions are supported:
      def supported?
        case connection.adapter_name
        when 'PostgreSQL', 'PostGIS'
          true
        when 'SQLite'
          Gem::Version.new(connection.select_value('SELECT sqlite_version()')) >= MINIMUM_SQLITE_VERSION
        else
          false
        end
      end

      # Register a limit policy for a given 'purpose' (stringy/symbol
      # identifier). This is optional and should not be used for dynamic purpose
      # names or limits, for memory and thread-safety reasons.
      def register!(purpose, max:, per:)
        raise ArgumentError, "Limit policy '#{purpose}' already registered" if limits.key?(purpose.to_sym)

        @limits = limits.merge(purpose.to_sym => { max: max, per: per }.freeze).freeze
      end

      # This method implements a leaky bucket algorithm (or, more specifically,
      # a Generic Cell Rate Algorithm) to enforce a per-'purpose' work limit.
      #
      # It will wait up to `wait_timeout` for the caller to come within the
      # configured limit before yielding to the caller, and will raise
      # `LimitExceededError` if the wait time would exceed that timeout (shedding
      # the caller proactively rather than sleeping).
      #
      # In Generic Cell Rate Algorithm (GCRA) terms:
      # - TAT (theoretical arrival time) -> drained_at
      # - T (emission interval)          -> drain_interval
      # - t0 (time of request)           -> the database's current time
      # - τ (bucket capacity)            -> 1 call (implicitly)
      #
      # IMPORTANT: For best results, the calling code MUST make its best attempt
      # to sleep for the returned 'wait' duration before proceeding. (Sleeping is
      # what shapes traffic to a smooth rate; it's best-effort, subject to
      # GIL / OS scheduling variability.)
      def within_limit(purpose, max: nil, per: nil, wait_timeout: 5.seconds)
        config = limits[purpose.to_sym]
        if config && (max || per)
          raise ArgumentError, "Limit policy '#{purpose}' is already registered (overriding 'max'/'per' is not supported)"
        end

        config ||= { max: max, per: per }.compact

        # The drain_interval reflects the per-call rate at which the bucket
        # empties, calculated as the overall interval (per) divided by the
        # maximum number of calls allowed in that interval (max).
        #
        # e.g. for a target of 100 req/min, the drain_interval would be 0.6 sec/req.
        drain_interval = config.fetch(:per).seconds / config.fetch(:max).to_d

        # Attempt to reserve capacity via an uncached database query:
        limit = connection.uncached do
          find_by_sql(reserve_sql(purpose, drain_interval, wait_timeout.seconds)).first
        end

        # If 'limit' is nil, it means the WHERE clause prevented us from
        # reserving capacity in the bucket. (This happens if the configured
        # `wait_timeout` would be exceeded.) We assume the caller will back off
        # and retry later, so we avoid wasting bucket capacity on a no-op.
        if limit.nil?
          ActiveSupport::Notifications.instrument('delayed.limit.exceeded', purpose: purpose)
          raise LimitExceededError, "Concurrency limit exceeded for '#{purpose}'"
        end

        # If we successfully reserved capacity within the `wait_timeout`, it
        # means that we've been told by the query how long to sleep in order to
        # comply with the configured rate.
        wait = limit.wait.to_f
        sleep(wait) if wait.positive?

        ActiveSupport::Notifications.instrument('delayed.limit.within_limit', purpose: purpose)
        yield
      end

      private

      # We reserve capacity by pushing a 'drained_at' timestamp forward by the
      # drain_interval, returning how long the caller must wait to avoid filling
      # the bucket beyond its capacity. (The WHERE clause significantly reduces
      # contention on the row when the bucket is full.)
      def reserve_sql(purpose, drain_interval, max_wait)
        case connection.adapter_name
        when 'PostgreSQL', 'PostGIS'
          # Postgres has native `interval` arithmetic and a statement-stable
          # clock (`statement_timestamp()`), so we bind the intervals as ISO8601
          # strings and let the database do the math.
          binds = { purpose: purpose, drain_interval: drain_interval.iso8601, max_wait: max_wait.iso8601 }
          [<<~SQL.squish, binds]
            INSERT INTO delayed_limits (purpose, drained_at)
            VALUES (:purpose, statement_timestamp() + :drain_interval)
            ON CONFLICT (purpose) DO UPDATE SET
              drained_at = GREATEST(statement_timestamp(), delayed_limits.drained_at) + :drain_interval
            WHERE delayed_limits.drained_at - statement_timestamp() <= :max_wait
            RETURNING EXTRACT(EPOCH FROM (drained_at - statement_timestamp() - :drain_interval)) AS wait
          SQL
        when 'SQLite'
          raise NotImplementedError, "Delayed::Limit requires SQLite #{MINIMUM_SQLITE_VERSION} or newer" unless supported?

          # SQLite has no interval type. Instead, `julianday` yields a
          # sub-second-precise number of days, and we bind the intervals as a
          # fraction of a day. (The `wait` is then scaled back to seconds.)
          binds = { purpose: purpose, drain_interval: drain_interval.to_f / SECONDS_PER_DAY, max_wait: max_wait.to_f / SECONDS_PER_DAY }
          [<<~SQL.squish, binds]
            INSERT INTO delayed_limits (purpose, drained_at)
            VALUES (:purpose, strftime('%Y-%m-%d %H:%M:%f', julianday('now') + :drain_interval))
            ON CONFLICT (purpose) DO UPDATE SET
              drained_at = strftime('%Y-%m-%d %H:%M:%f',
                MAX(julianday('now'), julianday(delayed_limits.drained_at)) + :drain_interval)
            WHERE julianday(delayed_limits.drained_at) - julianday('now') <= :max_wait
            RETURNING (julianday(drained_at) - julianday('now') - :drain_interval) * #{SECONDS_PER_DAY} AS wait
          SQL
        else
          raise NotImplementedError, "Delayed::Limit is not supported on #{connection.adapter_name.inspect}"
        end
      end
    end
  end
end
