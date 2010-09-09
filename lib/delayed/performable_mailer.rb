require 'action_mailer'

module Delayed
  class PerformableMailer < PerformableMethod
    def perform
      object.send(method_name, *args).deliver
    end
  end
end

ActionMailer::Base.class_eval do
  def self.delay(options = {})
    Delayed::DelayProxy.new(Delayed::PerformableMailer, self, options)
  end
end

Mail::Message.class_eval do
  def delay(*args)
    raise RuntimeError, "Use MyMailer.delay.mailer_action(args) to delay sending of emails."
  end
end