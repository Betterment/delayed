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
      job.scheduled_at = Time.at(timestamp) # rubocop:disable Rails/TimeZone
      _enqueue(job)
    end

    def enqueue_all(jobs)
      return 0 if jobs.empty?

      assert_jobs_safe_to_enqueue!(jobs)

      delayed_jobs = jobs.map { |job| build_delayed_job(job) }
      Delayed::Job.enqueue_all(delayed_jobs)

      perform_post_enqueue_assignments(jobs, delayed_jobs)

      jobs.size
    end

    private

    def _enqueue(job)
      job.tap { |j| enqueue_all([j]) }
    end

    def assert_jobs_safe_to_enqueue!(jobs)
      jobs.each do |job|
        if enqueue_after_transaction_commit_enabled?(job)
          raise UnsafeEnqueueError, "The ':delayed' ActiveJob adapter is not compatible with enqueue_after_transaction_commit"
        end
      end
    end

    def build_delayed_job(job)
      opts = { queue: job.queue_name, priority: job.priority }.compact
      opts.merge!(job.provider_attributes || {})
      opts[:run_at] = coerce_scheduled_at(job.scheduled_at) if job.scheduled_at

      prepared = Delayed::Backend::JobPreparer.new(JobWrapper.new(job), opts).prepare
      Delayed::Job.new(prepared)
    end

    def perform_post_enqueue_assignments(active_jobs, delayed_jobs)
      active_jobs.zip(delayed_jobs) do |active_job, delayed_job|
        active_job.successfully_enqueued = true if active_job.respond_to?(:successfully_enqueued=)
        active_job.provider_job_id = delayed_job.id
      end
    end

    def coerce_scheduled_at(value)
      value.is_a?(Numeric) ? Time.at(value) : value # rubocop:disable Rails/TimeZone
    end

    def enqueue_after_transaction_commit_enabled?(job)
      job.class.respond_to?(:enqueue_after_transaction_commit) &&
        [true, :always].include?(job.class.enqueue_after_transaction_commit)
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
