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
      warn "[DEPRECATION] `object.send_later(:method)` is deprecated. Use `object.delay.method"
      delay.__send__(method, *args)
    end

    def send_at(time, method, *args)
      warn "[DEPRECATION] `object.send_at(time, :method)` is deprecated. Use `object.delay(:run_at => time).method"
      delay(:run_at => time).__send__(method, *args)
    end
    
    module ClassMethods
      def handle_asynchronously(method)
        aliased_method, punctuation = method.to_s.sub(/([?!=])$/, ''), $1
        with_method, without_method = "#{aliased_method}_with_delay#{punctuation}", "#{aliased_method}_without_delay#{punctuation}"
        define_method(with_method) do |*args|
          delay.__send__(without_method, *args)
        end
        alias_method_chain method, :delay
      end
    end
  end                               
end