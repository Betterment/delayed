$:.unshift(File.dirname(__FILE__) + '/lib')
require 'rubygems'
require 'logger'
require 'delayed_job'
require 'benchmark'

Delayed::Worker.logger = Logger.new('/dev/null')

Benchmark.bm(10) do |x|
  [:active_record, :mongo_mapper, :data_mapper].each do |backend|
    require "spec/setup/#{backend}"
    Delayed::Worker.backend = backend
  
    n = 10000
    n.times { "foo".send_later :length }

    x.report(backend.to_s) { Delayed::Worker.new(:quiet => true).work_off(n) }
  end  
end
