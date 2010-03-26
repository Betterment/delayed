$:.unshift(File.dirname(__FILE__) + '/../lib')

require 'rubygems'
require 'spec'
require 'logger'

require 'delayed_job'
require 'sample_jobs'

Delayed::Worker.logger = Logger.new('/tmp/dj.log')

BACKENDS = [:active_record, :mongo_mapper]

BACKENDS.each do |backend|
  require "setup/#{backend}"
end

Delayed::Worker.backend = BACKENDS.first
