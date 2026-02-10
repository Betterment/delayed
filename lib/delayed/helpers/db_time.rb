# frozen_string_literal: true

module Delayed
  module Helpers
    module DbTime
      # Returns a SQL expression that evaluates to the current database time in UTC.
      # Unlike Job.db_time_now, this is evaluated by the database server, so it is
      # accurate even when the application server's clock or timezone is misconfigured.
      def self.sql_now_in_utc
        case ActiveRecord::Base.connection.adapter_name
        when 'PostgreSQL'
          "TIMEZONE('UTC', NOW())"
        when 'MySQL', 'Mysql2'
          "UTC_TIMESTAMP()"
        else
          "CURRENT_TIMESTAMP"
        end
      end

      # Parses a UTC timestamp returned by sql_now_in_utc. Handles both raw strings
      # and DateTime objects that Rails may have incorrectly tagged with local TZ info.
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

      # Returns the current database time, corrected for any offset between the
      # application server's clock and the database server's clock. The offset is
      # computed once (on first call) and cached for the lifetime of the process.
      def self.now
        Job.db_time_now + offset
      end

      # Returns the offset (in seconds) between the DB clock and the app clock.
      # A positive offset means the DB clock is ahead of the app clock.
      def self.offset
        @offset ||= compute_offset
      end

      def self.compute_offset
        app_time = Job.db_time_now
        db_time = parse_utc_time(
          Job.connection.select_value("SELECT #{sql_now_in_utc}"),
        )
        db_time - app_time
      end
      private_class_method :compute_offset
    end
  end
end
