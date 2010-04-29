module Delayed
  class DelayProxy < ActiveSupport::BasicObject
    def initialize(target, options)
      @target = target
      @options = options
    end
    
    def method_missing(method, *args)
      Delayed::Job.create @options.merge(
        :payload_object => Delayed::PerformableMethod.new(@target, method.to_sym, args)
      )
    end
  end
  
  module MessageSending
    def delay(options = {})
      DelayProxy.new(self, options)
    end
    
    def send_later(method, *args)
      Delayed::Job.enqueue Delayed::PerformableMethod.new(self, method.to_sym, args)
    end

    def send_at(time, method, *args)
      Delayed::Job.enqueue(Delayed::PerformableMethod.new(self, method.to_sym, args), 0, time)
    end
    
    module ClassMethods
      def handle_asynchronously(method)
        aliased_method, punctuation = method.to_s.sub(/([?!=])$/, ''), $1
        with_method, without_method = "#{aliased_method}_with_send_later#{punctuation}", "#{aliased_method}_without_send_later#{punctuation}"
        define_method(with_method) do |*args|
          send_later(without_method, *args)
        end
        alias_method_chain method, :send_later
      end
    end
  end                               
end