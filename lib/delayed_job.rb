require 'active_support'

require File.dirname(__FILE__) + '/delayed/message_sending'
require File.dirname(__FILE__) + '/delayed/performable_method'
require File.dirname(__FILE__) + '/delayed/backend/base'
require File.dirname(__FILE__) + '/delayed/worker'

Object.send(:include, Delayed::MessageSending)   
Module.send(:include, Delayed::MessageSending::ClassMethods)

if defined?(ActiveRecord)
  Delayed::Worker.backend = :active_record
elsif defined?(MongoMapper)
  Delayed::Worker.backend = :mongo_mapper
else
  $stderr.puts "Could not decide on a backend, defaulting to active_record"
  Delayed::Worker.backend = :active_record
end

if defined?(Merb::Plugins)
  Merb::Plugins.add_rakefiles File.dirname(__FILE__) / 'delayed' / 'tasks'
end
