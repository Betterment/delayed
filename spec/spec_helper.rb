$:.unshift(File.dirname(__FILE__) + '/../lib')

require 'rubygems'
require 'spec'
require 'logger'

require 'delayed_job'
require 'sample_jobs'
require 'database_cleaner'

Delayed::Worker.logger = Logger.new('/tmp/dj.log')

BACKENDS = [:active_record, :mongo_mapper, :data_mapper]

BACKENDS.each do |backend|
  require "setup/#{backend}"
end

Delayed::Worker.backend = BACKENDS.first
DatabaseCleaner.orm = BACKENDS.first.to_s
DatabaseCleaner.strategy = :truncation