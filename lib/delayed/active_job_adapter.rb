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

    # `perform_all_later` / `enqueue_all` is an ActiveJob 7.1+ feature.
    # Earlier ActiveJob versions lack both the caller (`perform_all_later`)
    # and the per-job `successfully_enqueued=` setter, so we gate only the
    # public method — the private helpers are unconditional and just unused
    # on <7.1.
    if ActiveJob.gem_version >= Gem::Version.new('7.1')
      def enqueue_all(jobs)
        return 0 if jobs.empty?

        jobs.each do |job|
          if enqueue_after_transaction_commit_enabled?(job)
            raise UnsafeEnqueueError, "The ':delayed' ActiveJob adapter is not compatible with enqueue_after_transaction_commit"
          end
        end

        # Fall back to the per-job path when we can't take the bulk shortcut.
        return enqueue_all_one_by_one(jobs) unless bulk_enqueue_supported?

        rows = jobs.map { |job| build_insert_row(job) }
        result = Delayed::Job.insert_all(rows, record_timestamps: true) # rubocop:disable Rails/SkipsModelValidations
        ids = result.rows.map(&:first)

        jobs.zip(ids) do |job, id|
          job.provider_job_id = id
          job.successfully_enqueued = true
        end

        ids.size
      end
    end

    private

    # Bulk enqueue needs to return the new IDs so we can populate
    # `provider_job_id` on each input job. That requires both:
    #   - delay_jobs = true (otherwise each job runs inline via `save`/`invoke_job`)
    #   - an adapter that supports INSERT ... RETURNING (MySQL does not)
    def bulk_enqueue_supported?
      Delayed::Worker.delay_jobs == true && Delayed::Job.connection.supports_insert_returning?
    end

    def build_insert_row(job)
      opts = { queue: job.queue_name, priority: job.priority }.compact
      opts.merge!(job.provider_attributes || {})
      opts[:run_at] = coerce_scheduled_at(job.scheduled_at) if job.scheduled_at

      prepared = Delayed::Backend::JobPreparer.new(JobWrapper.new(job), opts).prepare
      dj = Delayed::Job.new(prepared)

      Delayed.lifecycle.run_callbacks(:enqueue, dj) do
        dj.hook(:enqueue)
      end

      # Replicate `before_save` hooks since insert_all bypasses callbacks.
      dj.before_save_hooks
      dj.attributes.compact
    end

    def coerce_scheduled_at(value)
      value.is_a?(Numeric) ? Time.at(value) : value # rubocop:disable Rails/TimeZone
    end

    def enqueue_all_one_by_one(jobs)
      jobs.count do |job|
        opts = job.scheduled_at ? { run_at: coerce_scheduled_at(job.scheduled_at) } : {}
        _enqueue(job, opts)
        job.successfully_enqueued = true
        true
      end
    end

    def _enqueue(job, opts = {})
      if enqueue_after_transaction_commit_enabled?(job)
        raise UnsafeEnqueueError, "The ':delayed' ActiveJob adapter is not compatible with enqueue_after_transaction_commit"
      end

      opts.merge!({ queue: job.queue_name, priority: job.priority }.compact)
        .merge!(job.provider_attributes || {})

      Delayed::Job.enqueue(JobWrapper.new(job), opts).tap do |dj|
        job.provider_job_id = dj.id
      end
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
