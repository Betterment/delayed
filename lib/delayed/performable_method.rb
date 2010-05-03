module Delayed
  class PerformableMethod < Struct.new(:object, :method, :args)
    def initialize(object, method, args)
      raise NoMethodError, "undefined method `#{method}' for #{object.inspect}" unless object.respond_to?(method)

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
  end
end
