namespace :delayed do
  task delayed_environment: :environment do
    Delayed::Worker.min_priority = ENV['MIN_PRIORITY'].to_i if ENV.key?('MIN_PRIORITY')
    Delayed::Worker.max_priority = ENV['MAX_PRIORITY'].to_i if ENV.key?('MAX_PRIORITY')
    Delayed::Worker.queues = [ENV['QUEUE']] if ENV.key?('QUEUE')
    Delayed::Worker.queues = ENV['QUEUES'].split(',') if ENV.key?('QUEUES')
    Delayed::Worker.sleep_delay = ENV['SLEEP_DELAY'].to_i if ENV.key?('SLEEP_DELAY')
    Delayed::Worker.read_ahead = ENV['READ_AHEAD'].to_i if ENV.key?('READ_AHEAD')
    Delayed::Worker.max_claims = ENV['MAX_CLAIMS'].to_i if ENV.key?('MAX_CLAIMS')

    next unless defined?(Rails.application.config)

    # By default, Rails < 6.1 overrides eager_load to 'false' inside of rake tasks, which is not ideal in production environments.
    # Additionally, the classic Rails autoloader is not threadsafe, so we do not want any autoloading after we start the worker.
    # While the zeitwork autoloader technically does not need this workaround, we will still eager load for consistency's sake.
    # We will use the cache_classes config as a proxy for determining if we should eager load before booting workers.
    if !Rails.application.config.respond_to?(:rake_eager_load) && Rails.application.config.cache_classes
      Rails.application.config.eager_load = true
      Rails::Application::Finisher.initializers
        .find { |i| i.name == :eager_load! }
        .bind(Rails.application)
        .run
    end
  end

  desc 'start a delayed worker'
  task work: :delayed_environment do
    Delayed::Worker.new.start
  end

  desc 'monitor job queue and emit metrics at an interval'
  task monitor: :delayed_environment do
    Delayed::Monitor.new.start
  end
end

# For backwards compatibility:
namespace :jobs do
  task work: %i(delayed:work)
end
