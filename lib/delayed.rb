require 'active_support'
require 'active_support/core_ext/numeric/time'
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

if defined?(Rails::Engine)
  require 'delayed/engine'
else
  require 'active_record'
  require_relative '../app/models/delayed/job'
end

ActiveSupport.on_load(:active_job) do
  require 'delayed/active_job_adapter'
  ActiveJob::QueueAdapters::DelayedAdapter = Class.new(Delayed::ActiveJobAdapter)

  include Delayed::ActiveJobAdapter::EnqueuingPatch
end

ActiveSupport.on_load(:action_mailer) do
  require 'delayed/performable_mailer'
  ActionMailer::Base.extend(Delayed::DelayMail)
  ActionMailer::Parameterized::Mailer.include(Delayed::DelayMail) if defined?(ActionMailer::Parameterized::Mailer)
end

module Delayed
  autoload :PerformableMailer, 'delayed/performable_mailer'

  mattr_accessor(:default_log_level) { 'info'.freeze }
  mattr_accessor(:plugins) do
    [
      Delayed::Plugins::Instrumentation,
      Delayed::Plugins::Connection,
    ]
  end

  def self.lifecycle
    setup_lifecycle unless @lifecycle
    @lifecycle
  end

  def self.setup_lifecycle
    @lifecycle = Delayed::Lifecycle.new
    plugins.each { |klass| klass.new }
  end

  def self.logger
    @logger ||= Rails.logger
  end

  def self.logger=(value)
    @logger = value
  end

  def self.say(message, level = default_log_level)
    logger&.send(level, message)
  end
end

Object.include Delayed::MessageSending
Module.include Delayed::MessageSendingClassMethods
