module Delayed
  module Backend
    class JobPreparer
      attr_reader :options, :args

      def initialize(*args)
        @options = args.extract_options!.dup
        @args = args
      end

      def prepare
        set_payload
        set_queue_name
        set_priority
        handle_deprecation
        options
      end

      private

      def set_payload
        options[:payload_object] ||= args.shift
      end

      def set_queue_name
        options[:queue] ||= options[:payload_object].queue_name if options[:payload_object].respond_to?(:queue_name)
        options[:queue] ||= Delayed::Worker.default_queue_name
      end

      def set_priority
        options[:priority] ||= options[:payload_object].priority if options[:payload_object].respond_to?(:priority)
        options[:priority] ||= Delayed::Worker.default_priority
      end

      def handle_deprecation
        unless options[:payload_object].respond_to?(:perform)
          raise ArgumentError,
                'Cannot enqueue items which do not respond to perform'
        end
      end
    end
  end
end
