module Delayed
  class JobWrapper # rubocop:disable Betterment/ActiveJobPerformable
    attr_accessor :job_data

    delegate_missing_to :job

    def initialize(job_or_data)
      # During enqueue the job instance is passed in directly, saves us deserializing
      # it to find out how to queue the job.
      # During load from the db, we get a data hash passed in so deserialize lazily.
      if job_or_data.is_a?(ActiveJob::Base)
        @job = job_or_data
        @job_data = job.serialize
      else
        @job_data = job_or_data
      end
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
      return @job if defined?(@job)

      @job = ActiveJob::Base.deserialize(job_data) if job_data
    end
  end
end
