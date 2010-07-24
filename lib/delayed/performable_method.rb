module Delayed
  class PerformableMethod < Struct.new(:object, :method, :args)
    def initialize(object, method, args)
      raise NoMethodError, "undefined method `#{method}' for #{object.inspect}" unless object.respond_to?(method, true)

      self.object = object
      self.args   = args
      self.method = method.to_sym
    end
    
    def display_name
      "#{object.class}##{method}"
    end
    
    def perform
      object.send(method, *args) if object
    end
    
    def method_missing(symbol, *args)
      object.respond_to?(symbol) ? object.send(symbol, *args) : super
    end
       
    def respond_to?(symbol, include_private=false)
      object.respond_to?(symbol, include_private) || super
    end    
  end
end
