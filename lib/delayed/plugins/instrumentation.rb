module Delayed
  module Plugins
    class Instrumentation < Plugin
      callbacks do |lifecycle|
        lifecycle.around(:enqueue) do |job, *args, &block|
          ActiveSupport::Notifications.instrument('delayed.job.enqueue', active_support_notifications_tags(job)) do
            block.call(job, *args)
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
    end
  end
end
