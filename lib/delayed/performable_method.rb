module Delayed
  class PerformableMethod < Struct.new(:object, :method, :args)
    CLASS_STRING_FORMAT = /^CLASS\:([A-Z][\w\:]+)$/
    AR_STRING_FORMAT    = /^AR\:([A-Z][\w\:]+)\:(\d+)$/
    MM_STRING_FORMAT    = /^MM\:([A-Z][\w\:]+)\:(\w+)$/
    
    class LoadError < StandardError
    end

    def initialize(object, method, args)
      raise NoMethodError, "undefined method `#{method}' for #{self.inspect}" unless object.respond_to?(method)

      self.object = dump(object)
      self.args   = args.map { |a| dump(a) }
      self.method = method.to_sym
    end
    
    def display_name  
      case self.object
      when CLASS_STRING_FORMAT then "#{$1}.#{method}"
      when AR_STRING_FORMAT    then "#{$1}##{method}"
      when MM_STRING_FORMAT    then "#{$1}##{method}"
      else "Unknown##{method}"
      end      
    end    

    def perform
      load(object).send(method, *args.map{|a| load(a)})
    rescue PerformableMethod::LoadError
      # We cannot do anything about objects which were deleted in the meantime
      true
    end

    private

    def load(obj)
      case obj
      when CLASS_STRING_FORMAT then $1.constantize
      when AR_STRING_FORMAT    then $1.constantize.find($2)
      when MM_STRING_FORMAT    then $1.constantize.find!($2)
      else obj
      end
    rescue => e
      Delayed::Worker.logger.warn "Could not load object for job: #{e.message}"
      raise PerformableMethod::LoadError
    end

    def dump(obj)
      case obj
      when Class                  then "CLASS:#{obj.name}"
      when ActiveRecord::Base     then "AR:#{obj.class}:#{obj.id}"
      when MongoMapper::Document  then "MM:#{obj.class}:#{obj.id}"
      else obj
      end
    end
  end
end