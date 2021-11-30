require 'active_support/proxy_object'

module Delayed
  class DelayProxy < ActiveSupport::ProxyObject
    def initialize(payload_class, target, options)
      @payload_class = payload_class
      @target = target
      @options = options
    end

    def method_missing(method, *args, **kwargs)
      Job.enqueue({ payload_object: @payload_class.new(@target, method.to_sym, args, kwargs) }.merge(@options))
    end
  end

  module MessageSending
    def delay(options = {})
      DelayProxy.new(PerformableMethod, self, options)
    end
    alias __delay__ delay
  end

  module MessageSendingClassMethods
    def handle_asynchronously(method, opts = {}) # rubocop:disable Metrics/PerceivedComplexity
      aliased_method = method.to_s.sub(/([?!=])$/, '')
      punctuation = $1 # rubocop:disable Style/PerlBackrefs
      with_method = "#{aliased_method}_with_delay#{punctuation}"
      without_method = "#{aliased_method}_without_delay#{punctuation}"
      define_method(with_method) do |*args, **kwargs|
        curr_opts = opts.clone
        curr_opts.each_key do |key|
          next unless (val = curr_opts[key]).is_a?(Proc)

          curr_opts[key] = if val.arity == 1
                             val.call(self)
                           else
                             val.call
                           end
        end
        delay(curr_opts).__send__(without_method, *args, **kwargs)
      end

      alias_method without_method, method
      alias_method method, with_method

      if public_method_defined?(without_method)
        public method
      elsif protected_method_defined?(without_method)
        protected method
      elsif private_method_defined?(without_method)
        private method
      end
    end
  end
end
