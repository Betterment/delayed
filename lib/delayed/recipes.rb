# Capistrano Recipes for managing delayed_job
#
# Add these callbacks to have the delayed_job process restart when the server
# is restarted:
#
#   after "deploy:stop",    "delayed_job:stop"
#   after "deploy:start",   "delayed_job:start"
#   after "deploy:restart", "delayed_job:restart"

Capistrano::Configuration.instance.load do
  namespace :delayed_job do
    desc "Stop the delayed_job process"
    task :stop, :roles => :app do
      run "cd #{current_path}; RAILS_ENV=#{rails_env} script/delayed_job stop"
    end

    desc "Start the delayed_job process"
    task :start, :roles => :app do
      run "cd #{current_path}; RAILS_ENV=#{rails_env} script/delayed_job start"
    end

    desc "Restart the delayed_job process"
    task :restart, :roles => :app do
      run "cd #{current_path}; RAILS_ENV=#{rails_env} script/delayed_job restart"
    end
  end
end