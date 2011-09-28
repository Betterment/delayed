require 'active_support'

require File.dirname(__FILE__) + '/delayed/message_sending'
require File.dirname(__FILE__) + '/delayed/performable_method'

# PerformableMailer is compatible with ActionMailer 3 (and possibly 3.1)
if defined?(ActionMailer)
  require 'action_mailer/version'
  require File.dirname(__FILE__) + '/delayed/performable_mailer' if 3 == ActionMailer::VERSION::MAJOR
end

require File.dirname(__FILE__) + '/delayed/yaml_ext'
require File.dirname(__FILE__) + '/delayed/lifecycle'
require File.dirname(__FILE__) + '/delayed/plugin'
require File.dirname(__FILE__) + '/delayed/plugins/clear_locks'
require File.dirname(__FILE__) + '/delayed/backend/base'
require File.dirname(__FILE__) + '/delayed/worker'
require File.dirname(__FILE__) + '/delayed/deserialization_error'
require File.dirname(__FILE__) + '/delayed/railtie' if defined?(Rails::Railtie)

Object.send(:include, Delayed::MessageSending)
Module.send(:include, Delayed::MessageSending::ClassMethods)
