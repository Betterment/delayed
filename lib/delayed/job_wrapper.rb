module Delayed
  class JobWrapper # rubocop:disable Betterment/ActiveJobPerformable
    module HookDeprecation
      Delayed::Backend::Base::HOOKS.each do |hook|
        define_method(hook) do |*args|
          if respond_to_missing?(hook, false)
            warn "[DEPRECATION] Job hook methods (`#{hook}`) are deprecated. Use ActiveJob callbacks instead."
            super(*args)
          end
        end
      end
    end
    include HookDeprecation

    attr_accessor :job_data

    delegate_missing_to :job

    def initialize(job_or_data)
      # During enqueue the job instance is passed in directly, saves us deserializing
      # it to find out how to queue the job.
      # During load from the db, we get a data hash passed in so deserialize lazily.
      if job_or_data.is_a?(ActiveJob::Base)
        @job = job_or_data
        @job_data = job_or_data.serialize
      else
        @job_data = job_or_data
      end
    end

    def display_name
      job_data['job_class']
    end

    # If job failed to deserialize, we can't respond to delegated methods.
    # Returning false here prevents instance method checks from blocking job cleanup.
    # Rails 8.1+ raises ActiveJob::UnknownJobClassError (rails/rails#53770).
    if Gem::Version.new(ActiveJob.version) >= Gem::Version.new('8.1')
      def respond_to?(*, **)
        super
      rescue ActiveJob::UnknownJobClassError
        false
      end
    else
      def respond_to?(*, **)
        super
      rescue NameError
        false
      end
    end

    def before(record)
      # ActiveJob retries should use the row's current priority (it may have changed since enqueue):
      self.priority = record.priority.to_i if respond_to?(:priority=)
      # If a job is manually reset, we reset ActiveJob's execution log as well:
      reset_execution_log! if job_data.delete('terminated_at') && record.attempts.zero?
      super
    end

    def error(record, error)
      # The error escaped retry_on (if any), so ActiveJob considers the job terminated.
      job_data['terminated_at'] = record.class.db_time_now.utc.iso8601(9)
      record.payload_object = self # re-serialize the handler
      super
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

    def reset_execution_log!
      job_data['executions'] = 0
      job_data['exception_executions'] = {}
      self.executions = job_data['executions'] if respond_to?(:executions=)
      self.exception_executions = job_data['exception_executions'] if respond_to?(:exception_executions=)
    end

    def job
      @job ||= ActiveJob::Base.deserialize(job_data) if job_data
    end
  end
end
