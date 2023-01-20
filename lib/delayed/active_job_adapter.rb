module Delayed
  class ActiveJobAdapter
    def enqueue(job)
      _enqueue(job)
    end

    def enqueue_at(job, timestamp)
      _enqueue(job, run_at: Time.at(timestamp)) # rubocop:disable Rails/TimeZone
    end

    private

    def _enqueue(job, opts = {})
      opts.merge!({ queue: job.queue_name, priority: job.priority }.compact)
        .merge!(job.provider_attributes || {})

      Delayed::Job.enqueue(JobWrapper.new(job.serialize), opts).tap do |dj|
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

  class JobWrapper # rubocop:disable Betterment/ActiveJobPerformable
    attr_accessor :job_data

    delegate_missing_to :job

    def initialize(job_data)
      @job_data = job_data
    end

    def display_name
      job_data['job_class']
    end

    def perform
      ActiveJob::Callbacks.run_callbacks(:execute) do
        job.perform_now
      end
    end

    def encode_with(coder)
      coder['job_data'] = @job_data
    end

    private

    def job
      @job ||= ActiveJob::Base.deserialize(job_data) if job_data
    end
  end
end
