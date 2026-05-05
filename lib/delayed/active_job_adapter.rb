module Delayed
  class ActiveJobAdapter
    class UnsafeEnqueueError < RuntimeError; end

    def enqueue_after_transaction_commit?
      false
    end

    def enqueue(job)
      enqueue_all([job])
      job
    end

    def enqueue_at(job, timestamp)
      job.scheduled_at = Time.at(timestamp) # rubocop:disable Rails/TimeZone
      enqueue_all([job])
      job
    end

    def enqueue_all(jobs)
      return 0 if jobs.empty?

      assert_safe_to_enqueue!(jobs)

      Delayed.lifecycle.run_callbacks(:enqueue, jobs) do
        now = Delayed::Job.db_time_now
        rows = jobs.map { |job| build_insert_row(job, now) }
        result = Delayed::Job.insert_all(rows) # rubocop:disable Rails/SkipsModelValidations
        assign_provider_job_ids(jobs, result) if Delayed::Job.connection.supports_insert_returning?
      end

      mark_successfully_enqueued(jobs)
      jobs.size
    end

    private

    def assert_safe_to_enqueue!(jobs)
      if jobs.any? { |job| enqueue_after_transaction_commit_enabled?(job) }
        raise UnsafeEnqueueError, "The ':delayed' ActiveJob adapter is not compatible with enqueue_after_transaction_commit"
      end
      unless Delayed::Worker.delay_jobs == true
        raise UnsafeEnqueueError, "The ':delayed' ActiveJob adapter is not compatible with delay_jobs false"
      end
    end

    def assign_provider_job_ids(jobs, result)
      ids = result.rows.map(&:first)
      jobs.zip(ids) { |job, id| job.provider_job_id = id }
    end

    def mark_successfully_enqueued(jobs)
      jobs.each { |job| job.successfully_enqueued = true if job.respond_to?(:successfully_enqueued=) }
    end

    def build_insert_row(job, now)
      opts = { queue: job.queue_name, priority: job.priority }.compact
      opts.merge!(job.provider_attributes || {})
      opts[:run_at] = coerce_scheduled_at(job.scheduled_at) if job.scheduled_at

      prepared = Delayed::Backend::JobPreparer.new(JobWrapper.new(job), opts).prepare
      Delayed::Job.new(prepared).attributes.compact.merge('created_at' => now, 'updated_at' => now)
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
