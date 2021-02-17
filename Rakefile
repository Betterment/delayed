require 'bundler/setup'
Bundler::GemHelper.install_tasks

require 'rspec/core/rake_task'
desc 'Run the specs'
RSpec::Core::RakeTask.new do |r|
  r.verbose = false
end

require 'rubocop/rake_task'
RuboCop::RakeTask.new

if ENV['APPRAISAL_INITIALIZED'] || ENV['CI']
  tasks = [:spec]
  tasks += [:rubocop] unless ENV['CI']

  task :default => tasks
else
  require 'appraisal'
  Appraisal::Task.new
  task :default => :appraisal
end
