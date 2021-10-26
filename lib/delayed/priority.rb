module Delayed
  class Priority < Numeric
    # A Delayed::Priority represents a value that exists within a named range.
    # Here are the default ranges and their names:
    #
    #   0-9: interactive
    # 10-19: user_visible
    # 20-29: eventual
    #   30+: reporting
    #
    # Ranges can be customized. They must be positive and must include a name for priority >= 0.
    # The following config will produce ranges 0-99 (high), 100-499 (medium) and 500+ (low):
    #
    # > Delayed::Priority.names = { high: 0, medium: 100, low: 500 }

    DEFAULT_NAMES = {
      interactive: 0, # These jobs will actively hinder end-user interactions until they are complete, e.g. work behind a loading spinner
      user_visible: 10, # These jobs have end-user-visible side effects that will not obviously impact customers, e.g. welcome emails
      eventual: 20, # These jobs affect business process that are tolerant to some degree of queue backlog, e.g. syncing with other services
      reporting: 30, # These jobs are for processes that can complete on a slower timeline, e.g. daily report generation
    }.freeze

    # Priorities can be mapped to alerting thresholds for job age (time since run_at), runtime, and attempts.
    # These thresholds can be used to emit events or metrics. Here are the default values (for the default priorities):
    #
    # === Age Alerts ==========
    #   interactive: 1 minute
    #  user_visible: 3 minutes
    #      eventual: 1.5 hours
    #     reporting: 4 hours
    #
    # === Run Time Alerts ======
    #   interactive: 30 seconds
    #  user_visible: 90 seconds
    #      eventual: 5 minutes
    #     reporting: 10 minutes
    #
    # === Attempts Alerts =====
    #   interactive: 3 attempts
    #  user_visible: 5 attempts
    #      eventual: 8 attempts
    #     reporting: 8 attempts
    #
    # Alerting thresholds can be customized. The keys must match `Delayed::Priority.names`.
    #
    # Delayed::Priority.alerts = {
    #   high: { age: 30.seconds, run_time: 15.seconds, attempts: 3 },
    #   medium: { age: 2.minutes, run_time: 1.minute, attempts: 6 },
    #   low: { age: 10.minutes, run_time: 2.minutes, attempts: 9 },
    # }

    DEFAULT_ALERTS = {
      interactive: { age: 1.minute, run_time: 30.seconds, attempts: 3 },
      user_visible: { age: 3.minutes, run_time: 90.seconds, attempts: 5 },
      eventual: { age: 1.5.hours, run_time: 5.minutes, attempts: 8 },
      reporting: { age: 4.hours, run_time: 10.minutes, attempts: 8 },
    }.freeze

    class << self
      def names
        @names || default_names
      end

      def alerts
        @alerts || default_alerts
      end

      def names=(names)
        raise "must include a name for priority >= 0" if names && !names.value?(0)

        @ranges = nil
        @alerts = nil
        @names = names&.sort_by(&:last)&.to_h&.transform_values { |v| new(v) }
      end

      def alerts=(alerts)
        if alerts
          unknown_names = alerts.keys - names.keys
          raise "unknown priority name(s): #{unknown_names}" if unknown_names.any?
        end

        @alerts = alerts&.sort_by { |k, _| names.keys.index(k) }&.to_h
      end

      def ranges
        @ranges ||= names.zip(names.except(names.keys.first)).each_with_object({}) do |((name, lower), (_, upper)), obj|
          obj[name] = (lower...(upper || Float::INFINITY))
        end
      end

      private

      def default_names
        @default_names ||= DEFAULT_NAMES.transform_values { |v| new(v) }
      end

      def default_alerts
        @names ? {} : DEFAULT_ALERTS
      end

      def respond_to_missing?(method_name, include_private = false)
        names.key?(method_name) || super
      end

      def method_missing(method_name, *args)
        if names.key?(method_name) && args.none?
          names[method_name]
        else
          super
        end
      end
    end

    attr_reader :value

    delegate :to_i, to: :value
    delegate :to_s, to: :name

    def initialize(value)
      super()
      value = self.class.names[value] if value.is_a?(Symbol)
      @value = value.to_i
    end

    def name
      @name ||= self.class.ranges.find { |(_, r)| r.include?(to_i) }&.first
    end

    def alert_age
      self.class.alerts.dig(name, :age)
    end

    def alert_run_time
      self.class.alerts.dig(name, :run_time)
    end

    def alert_attempts
      self.class.alerts.dig(name, :attempts)
    end

    def coerce(other)
      [self.class.new(other), self]
    end

    def <=>(other)
      other = other.to_i if other.is_a?(self.class)
      to_i <=> other
    end

    private

    def respond_to_missing?(method_name, include_private = false)
      (method_name.to_s.end_with?('?') && self.class.names.key?(method_name.to_s[0..-2].to_sym)) || super
    end

    def method_missing(method_name, *args)
      if method_name.to_s.end_with?('?') && self.class.names.key?(method_name.to_s[0..-2].to_sym)
        method_name.to_s[0..-2] == to_s
      else
        super
      end
    end
  end
end
