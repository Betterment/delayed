$:.unshift(File.dirname(__FILE__) + '/../lib')

require 'rubygems'
require 'spec'
require 'logger'

backends_available = []
%w(active_record mongo_mapper).each do |backend|
  begin
    require backend
    backends_available << backend
  rescue LoadError => e
    $stderr.puts "The backend '#{backend}' is not available. Skipping tests"
  end
end

if backends_available.empty?
  raise LoadError, "Cannot run delayed_job specs. No backends available"
end

require 'delayed_job'
require 'sample_jobs'
require 'backend/shared_backend_spec'

DELAYED_JOB_LOGGER = Logger.new('/tmp/dj.log')
Delayed::Worker.logger = DELAYED_JOB_LOGGER

DEFAULT_BACKEND = backends_available.first.to_sym

backends_available.each do |backend|
  require "setup/#{backend}"
  require "backend/#{backend}_job_spec"
end
