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
        handle_dst
        reject_stale_run_at
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

      def scheduled_into_fall_back_hour?
        options[:run_at] &&
          !options[:run_at].in_time_zone.dst? &&
          (options[:run_at] - 1.hour).dst?
      end

      def handle_dst
        # The DB column does not retain timezone information. As a result, if we
        # are running with `:local` timezone, then any future-scheduled jobs
        # that fall into the "fall back" DST transition need to rounded up to
        # the later hour or they will cause a "spinloop" of immediate retries.
        if Job.default_timezone == :local && scheduled_into_fall_back_hour?
          run_at_was = options[:run_at]
          options[:run_at] = (run_at_was + 1.hour).beginning_of_hour
          Delayed.say("Adjusted run_at from #{run_at_was} to #{options[:run_at]} to account for fall back DST transition", :warn)
        end
      end

      def reject_stale_run_at
        return unless Delayed::Worker.deny_stale_enqueues
        return unless options[:run_at]

        threshold = Helpers::DbTime.now - Job.lock_timeout
        return unless options[:run_at] < threshold

        raise StaleEnqueueError,
              "Cannot enqueue a job in the distant past (run_at: #{options[:run_at].iso8601}," \
              " threshold: #{threshold.iso8601}). This is usually a bug."
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
