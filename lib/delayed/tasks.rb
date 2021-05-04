namespace :delayed do
  task environment_options: :environment do
    @worker_options = {
      min_priority: ENV['MIN_PRIORITY'],
      max_priority: ENV['MAX_PRIORITY'],
      queues: (ENV['QUEUES'] || ENV['QUEUE'] || '').split(','),
      quiet: ENV['QUIET'],
    }

    @worker_options[:sleep_delay] = ENV['SLEEP_DELAY'].to_i if ENV['SLEEP_DELAY']
    @worker_options[:read_ahead] = ENV['READ_AHEAD'].to_i if ENV['READ_AHEAD']
    @worker_options[:max_claims] = ENV['MAX_CLAIMS'].to_i if ENV['MAX_CLAIMS']
  end

  desc 'start a delayed worker'
  task work: :environment_options do
    Delayed::Worker.new(@worker_options).start
  end

  desc 'monitor job queue and emit metrics at an interval'
  task monitor: [:environment] do
    Delayed::Monitor.new.start
  end
end

# For backwards compatibility:
namespace :jobs do
  task work: %i(delayed:work)
end
