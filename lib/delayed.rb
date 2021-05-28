require 'active_support'
require 'delayed/exceptions'
require 'delayed/message_sending'
require 'delayed/performable_method'
require 'delayed/yaml_ext'
require 'delayed/lifecycle'
require 'delayed/runnable'
require 'delayed/priority'
require 'delayed/monitor'
require 'delayed/plugin'
require 'delayed/plugins/connection'
require 'delayed/plugins/instrumentation'
require 'delayed/backend/base'
require 'delayed/backend/job_preparer'
require 'delayed/worker'
require 'delayed/railtie' if defined?(Rails::Railtie)

ActiveSupport.on_load(:active_record) do
  require 'delayed/serialization/active_record'
  require 'delayed/job'
end

ActiveSupport.on_load(:action_mailer) do
  require 'delayed/performable_mailer'
  ActionMailer::Base.extend(Delayed::DelayMail)
  ActionMailer::Parameterized::Mailer.include(Delayed::DelayMail) if defined?(ActionMailer::Parameterized::Mailer)
end

module Delayed
  autoload :PerformableMailer, 'delayed/performable_mailer'
end

Object.include Delayed::MessageSending
Module.include Delayed::MessageSendingClassMethods
