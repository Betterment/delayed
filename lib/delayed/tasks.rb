namespace :delayed do
  task environment_options: :environment do
    Delayed::Worker.min_priority = ENV['MIN_PRIORITY'].to_i if ENV.key?('MIN_PRIORITY')
    Delayed::Worker.max_priority = ENV['MAX_PRIORITY'].to_i if ENV.key?('MAX_PRIORITY')
    Delayed::Worker.queues = [ENV['QUEUE']] if ENV.key?('QUEUE')
    Delayed::Worker.queues = ENV['QUEUES'].split(',') if ENV.key?('QUEUES')
    Delayed::Worker.sleep_delay = ENV['SLEEP_DELAY'].to_i if ENV.key?('SLEEP_DELAY')
    Delayed::Worker.read_ahead = ENV['READ_AHEAD'].to_i if ENV.key?('READ_AHEAD')
    Delayed::Worker.max_claims = ENV['MAX_CLAIMS'].to_i if ENV.key?('MAX_CLAIMS')
  end

  desc 'start a delayed worker'
  task work: :environment_options do
    Delayed::Worker.new.start
  end

  desc 'monitor job queue and emit metrics at an interval'
  task monitor: :environment_options do
    Delayed::Monitor.new.start
  end
end

# For backwards compatibility:
namespace :jobs do
  task work: %i(delayed:work)
end
