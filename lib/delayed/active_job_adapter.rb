module Delayed
  class ActiveJobAdapter
    class UnsafeEnqueueError < RuntimeError; end

    def enqueue_after_transaction_commit?
      false
    end

    def enqueue(job)
      _enqueue(job)
    end

    def enqueue_at(job, timestamp)
      _enqueue(job, run_at: Time.at(timestamp)) # rubocop:disable Rails/TimeZone
    end

    private

    def _enqueue(job, opts = {})
      if job.class.respond_to?(:enqueue_after_transaction_commit) && job.class.enqueue_after_transaction_commit
        raise UnsafeEnqueueError, "The ':delayed' ActiveJob adapter is not compatible with enqueue_after_transaction_commit"
      end

      opts.merge!({ queue: job.queue_name, priority: job.priority }.compact)
        .merge!(job.provider_attributes || {})

      Delayed::Job.enqueue(JobWrapper.new(job), opts).tap do |dj|
        job.provider_job_id = dj.id
      end
    end

    module EnqueuingPatch
      def self.included(klass)
        klass.prepend PrependedMethods
        klass.attr_accessor :provider_attributes
      end

      module PrependedMethods
        def enqueue(opts = {})
          raise "`:run_at` is not supported. Use `:wait_until` instead." if opts.key?(:run_at)

          self.provider_attributes = opts.except(:wait, :wait_until, :queue, :priority)
          opts[:priority] = Delayed::Priority.new(opts[:priority]) if opts.key?(:priority)
          super(opts)
        end
      end
    end
  end
end
