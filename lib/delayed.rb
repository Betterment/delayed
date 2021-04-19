require 'active_support'
require 'delayed/compatibility'
require 'delayed/exceptions'
require 'delayed/message_sending'
require 'delayed/performable_method'
require 'delayed/yaml_ext'
require 'delayed/lifecycle'
require 'delayed/plugin'
require 'delayed/plugins/clear_locks'
require 'delayed/backend/base'
require 'delayed/backend/job_preparer'
require 'delayed/worker'
require 'delayed/deserialization_error'
require 'delayed/railtie' if defined?(Rails::Railtie)

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

if defined?(Rails::Railtie)
  require 'delayed/backend/active_record/railtie'
else
  require 'active_record'
  require 'delayed/backend/active_record'

  Delayed::Worker.backend = :active_record
end
