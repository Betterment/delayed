module Delayed
  class PerformableMethod
    attr_accessor :object, :method_name, :args, :kwargs

    def initialize(object, method_name, args, kwargs)
      raise NoMethodError, "undefined method `#{method_name}' for #{object.inspect}" unless object.respond_to?(method_name, true)

      if !her_model?(object) && object.respond_to?(:persisted?) && !object.persisted?
        raise(ArgumentError, "job cannot be created for non-persisted record: #{object.inspect}")
      end

      self.object       = object
      self.args         = args
      self.kwargs       = kwargs
      self.method_name  = method_name.to_sym
    end

    def display_name
      if object.is_a?(Class)
        "#{object}.#{method_name}"
      else
        "#{object.class}##{method_name}"
      end
    end

    def perform
      return unless object

      if kwargs.nil? || (RUBY_VERSION < '2.7' && kwargs.empty?)
        object.send(method_name, *args)
      else
        object.send(method_name, *args, **kwargs)
      end
    end

    def method(sym)
      object.method(sym)
    end

    def method_missing(symbol, *args)
      object.send(symbol, *args)
    end

    def respond_to?(symbol, include_private = false)
      super || object.respond_to?(symbol, include_private)
    end

    private

    def her_model?(object)
      object.class.respond_to?(:save_existing)
    end
  end
end
