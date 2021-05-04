module Delayed
  module Plugins
    class Instrumentation < ::Delayed::Plugin
      callbacks do |lifecycle|
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
        connection_config = connection_config(job.class)
        {
          job_name: job.name,
          priority: job.priority,
          queue: job.queue,
          table: job.class.table_name,
          database: connection_config[:database],
          database_adapter: connection_config[:adapter],
          job: job,
        }
      end

      def self.connection_config(klass)
        if klass.respond_to?(:connection_db_config)
          klass.connection_db_config.configuration_hash # Rails >= 6.1
        else
          klass.connection_config # Rails < 6.1
        end
      end
    end
  end
end
