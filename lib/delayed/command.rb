require 'rubygems'
require 'daemons'
require 'optparse'

module Delayed
  class Command
    def initialize(args)
      @options = {:quiet => true}
      
      opts = OptionParser.new do |opts|
        opts.banner = "Usage: #{File.basename($0)} [options] start|stop|restart|run"

        opts.on('-h', '--help', 'Show this message') do
          puts opts
          exit 1
        end
        opts.on('-e', '--environment=NAME', 'Specifies the environment to run this delayed jobs under (test/development/production).') do |e|
          ENV['RAILS_ENV'] = e
        end
        opts.on('--min-priority N', 'Minimum priority of jobs to run.') do |n|
          @options[:min_priority] = n
        end
        opts.on('--max-priority N', 'Maximum priority of jobs to run.') do |n|
          @options[:max_priority] = n
        end
      end
      @args = opts.parse!(args)
    end
  
    def daemonize
      Daemons.run_proc('delayed_job', :dir => "#{RAILS_ROOT}/tmp/pids", :dir_mode => :normal, :ARGV => @args) do |*args|
        run
      end
    end
    
    def run
      require File.join(RAILS_ROOT, 'config', 'environment')
      
      # Replace the default logger
      logger = Logger.new(File.join(RAILS_ROOT, 'log', 'delayed_job.log'))
      logger.level = ActiveRecord::Base.logger.level
      ActiveRecord::Base.logger = logger
      ActiveRecord::Base.clear_active_connections!
      Delayed::Worker.logger = logger
      
      Delayed::Worker.new(@options).start  
    rescue => e
      logger.fatal e
      STDERR.puts e.message
      exit 1
    end
    
  end
end