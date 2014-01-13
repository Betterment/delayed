if defined?(ActiveRecord)
  ActiveRecord::Base.class_eval do
    # rubocop:disable BlockNesting
    if instance_methods.include?(:encode_with)
      def encode_with_override(coder)
        encode_with_without_override(coder)
        coder.tag = "!ruby/ActiveRecord:#{self.class.name}" if coder.respond_to?(:tag=)
      end
      alias_method :encode_with_without_override, :encode_with
      alias_method :encode_with, :encode_with_override
    else
      def encode_with(coder)
        coder['attributes'] = attributes
        coder.tag = "!ruby/ActiveRecord:#{self.class.name}" if coder.respond_to?(:tag=)
      end
    end
  end
end

module Delayed
  class PerformableMethod
    # serialize to YAML
    def encode_with(coder)
      coder.map = {
        'object' => object,
        'method_name' => method_name,
        'args' => args
      }
    end
  end
end

module Psych
  if VERSION.to_f < 1.3
    def self.load yaml, filename = nil, visitor = nil
      result = parse(yaml)
      result ? result.to_ruby(visitor) : result
    end
  else
    def self.load yaml, filename = nil, visitor = nil
      result = parse(yaml, filename)
      result ? result.to_ruby(visitor) : result
    end
  end

  module Nodes
    class Node
      if Gem::Version.new(VERSION) >= Gem::Version.new('2.0.2')
        def to_ruby(visitor)
          visitor ||= Visitors::ToRuby
          visitor.create.accept(self)
        end
      else
        def to_ruby(visitor)
          visitor ||= Visitors::ToRuby
          visitor.new.accept(self)
        end
      end
    end
  end
end

module Delayed
  module PsychExt
    class ToRuby < Psych::Visitors::ToRuby
      def visit_Psych_Nodes_Mapping_with_class(object) # rubocop:disable PerceivedComplexity, CyclomaticComplexity, MethodName
        return revive(Psych.load_tags[object.tag], object) if Psych.load_tags[object.tag]

        case object.tag
        when /^!ruby\/ActiveRecord:(.+)$/
          klass = resolve_class(Regexp.last_match[1])
          payload = Hash[*object.children.map { |c| accept c }]
          id = payload['attributes'][klass.primary_key]
          id = id.value if defined?(ActiveRecord::Attribute) && id.is_a?(ActiveRecord::Attribute)
          begin
            klass.unscoped.find(id)
          rescue ActiveRecord::RecordNotFound => error
            raise Delayed::DeserializationError, "ActiveRecord::RecordNotFound, class: #{klass}, primary key: #{id} (#{error.message})"
          end
        when /^!ruby\/Mongoid:(.+)$/
          klass = resolve_class(Regexp.last_match[1])
          payload = Hash[*object.children.map { |c| accept c }]
          id = payload['attributes']['_id']
          begin
            klass.find(id)
          rescue Mongoid::Errors::DocumentNotFound => error
            raise Delayed::DeserializationError, "Mongoid::Errors::DocumentNotFound, class: #{klass}, primary key: #{id} (#{error.message})"
          end
        when /^!ruby\/DataMapper:(.+)$/
          klass = resolve_class(Regexp.last_match[1])
          payload = Hash[*object.children.map { |c| accept c }]
          begin
            primary_keys = klass.properties.select(&:key?)
            key_names = primary_keys.map { |p| p.name.to_s }
            klass.get!(*key_names.map { |k| payload['attributes'][k] })
          rescue DataMapper::ObjectNotFoundError => error
            raise Delayed::DeserializationError, "DataMapper::ObjectNotFoundError, class: #{klass} (#{error.message})"
          end
        else
          visit_Psych_Nodes_Mapping_without_class(object)
        end
      end
      alias_method_chain :visit_Psych_Nodes_Mapping, :class

      def resolve_class_with_constantize(klass_name)
        klass_name.constantize
      rescue
        resolve_class_without_constantize(klass_name)
      end
      alias_method_chain :resolve_class, :constantize
    end
  end
end
