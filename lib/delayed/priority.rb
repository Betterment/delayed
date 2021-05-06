module Delayed
  class Priority < Numeric
    DEFAULT_NAMES = {
      interactive: 0, # These jobs will actively hinder end-user interactions until they are complete, e.g. work behind a loading spinner
      user_visible: 10, # These jobs have end-user-visible side effects that will not obviously impact customers, e.g. welcome emails
      eventual: 20, # These jobs affect business process that are tolerant to some degree of queue backlog, e.g. syncing with other services
      reporting: 30, # These jobs are for processes that can complete on a slower timeline, e.g. daily report generation
    }.freeze

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
    class << self
      def names
        @names || DEFAULT_NAMES
      end

      def names=(names)
        raise "must include a name for priority >= 0" if names && !names.value?(0)

        @ranges = nil
        @names = names&.sort_by(&:last)&.to_h&.transform_values { |p| Priority.new(p) }
      end

      def ranges
        @ranges ||= names.zip(names.except(names.keys.first)).each_with_object({}) do |((name, lower), (_, upper)), obj|
          obj[name] = (lower...(upper || Float::INFINITY))
        end
      end

      private

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

    def coerce(other)
      [self.class.new(other), self]
    end

    def <=>(other)
      other = other.to_i if other.is_a?(self.class)
      to_i <=> other
    end

    private

    def respond_to_missing?(method_name, include_private = false)
      method_name.to_s.end_with?('?') && self.class.names.key?(method_name.to_s[0..-2].to_sym) || super
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
