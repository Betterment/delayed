module Delayed
  module Plugins
    class Instrumentation < Plugin
      callbacks do |lifecycle|
        lifecycle.around(:enqueue) do |jobs, &block|
          ActiveSupport::Notifications.instrument('delayed.job.enqueue', bulk_enqueue_tags(jobs)) do
            block.call(jobs)
          end
        end

        lifecycle.around(:invoke_job) do |job, *args, &block|
          ActiveSupport::Notifications.instrument('delayed.job.run', active_support_notifications_tags(job)) do
            block.call(job, *args)
          end
        end

        lifecycle.after(:error) do |_worker, job, *_args|
          ActiveSupport::Notifications.instrument('delayed.job.error', active_support_notifications_tags(job))
        end

        lifecycle.after(:failure) do |_worker, job, *_args|
          ActiveSupport::Notifications.instrument('delayed.job.failure', active_support_notifications_tags(job))
        end
      end

      def self.active_support_notifications_tags(job)
        {
          job_name: job.name,
          priority: job.priority,
          queue: job.queue,
          table: job.class.table_name,
          database: job.class.database_name,
          database_adapter: job.class.database_adapter_name,
          job: job,
        }
      end

      def self.bulk_enqueue_tags(jobs)
        {
          count: jobs.size,
          **summarize(jobs),
          jobs: jobs,
        }
      end

      def self.summarize(jobs)
        seed = { job_name: Hash.new(0), database: Hash.new(0), database_adapter: Hash.new(0) }
        jobs.each_with_object(seed) do |job, acc|
          name = job.respond_to?(:name) ? job.name : job.class.name
          delayed_class = job.is_a?(Delayed::Job) ? job.class : Delayed::Job
          acc[:job_name][name] += 1
          acc[:database][delayed_class.database_name] += 1
          acc[:database_adapter][delayed_class.database_adapter_name] += 1
        end
      end
    end
  end
end
