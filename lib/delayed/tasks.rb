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

    # By default, Rails wants to disable eager loading inside of `rake`
    # commands, even if `eager_load` is set to true. This is done to speed up
    # the boot time of rake tasks that don't need the entire application loaded.
    #
    # The problem is that long-lived processes like `delayed` **do** want to
    # eager load the application before spawning any threads or forks.
    # (Especially if in a production environment where we want full load-order
    # parity with the `rails server` processes!)
    #
    # When a Rails app boots, it chooses whether to eager load based on its
    # `eager_load` config and whether or not it was initiated by a `rake`
    # command. If it did eager load, we don't want to eager load again, but if
    # it was initiated by a `rake` command, it sets `eager_load` to false before
    # the point at which `delayed` starts setting up _its_ rake environment.
    #
    # So we cannot rely on that config to know whether or not to eager load --
    # instead we must make an inference:
    # - Newer rails versions (~7.0+) have a `config.rake_eager_load` option,
    # which tells us whether the app has already eager loaded in a `rake`
    # context.
    # - If `rake_eager_loading` is not defined or `false`, we will then check
    # `cache_classes` & explicitly eager load if true.

    eager_loaded = Rails.application.config.respond_to?(:rake_eager_load) && Rails.application.config.rake_eager_load
    next if eager_loaded || !Rails.application.config.cache_classes

    Rails.application.config.eager_load = true
    Rails::Application::Finisher.initializers
      .find { |i| i.name == :eager_load! }
      .bind(Rails.application)
      .run
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
