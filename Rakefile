require 'bundler/gem_helper'
Bundler::GemHelper.install_tasks

require 'rspec/core/rake_task'

ADAPTERS = %w(mysql2 postgresql sqlite3).freeze

ADAPTERS.each do |adapter|
  desc "Run RSpec code examples for #{adapter} adapter"
  RSpec::Core::RakeTask.new(adapter => "#{adapter}:adapter")

  namespace adapter do
    task :adapter do
      ENV['ADAPTER'] = adapter
    end
  end
end

task :adapter do
  ENV['ADAPTER'] = nil
end

require 'rubocop/rake_task'
RuboCop::RakeTask.new

if ENV['APPRAISAL_INITIALIZED'] || ENV['CI']
  tasks = ADAPTERS + [:adapter]
  tasks += [:rubocop] unless ENV['CI']

  task default: tasks
else
  require 'appraisal'
  Appraisal::Task.new
  task default: :appraisal
end
