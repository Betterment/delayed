module Delayed
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
