module Delayed
  class PerformableMethod
    # serialize to YAML
    def encode_with(coder)
      coder.map = {
        'object' => object,
        'method_name' => method_name,
        'args' => args,
        'kwargs' => kwargs,
      }
    end
  end
end

module Psych
  def self.load_dj(yaml)
    result = parse(yaml)
    result ? Delayed::PsychExt::ToRuby.create.accept(result) : result
  end

  def self.dump_dj(object)
    visitor = Delayed::PsychExt::YAMLTree.create
    visitor << object
    visitor.tree.yaml
  end
end

module Delayed
  module PsychExt
    class YAMLTree < Psych::Visitors::YAMLTree
      def accept(target)
        if defined?(ActiveRecord::Base) && target.is_a?(ActiveRecord::Base)
          tag = ['!ruby/ActiveRecord', target.class.name].compact.join(':')
          map = @emitter.start_mapping(nil, tag, false, Psych::Nodes::Mapping::BLOCK)
          register(target, map)
          @emitter.scalar('attributes', nil, nil, true, false, Psych::Nodes::Mapping::ANY)
          accept target.attributes.slice(target.class.primary_key)

          @emitter.end_mapping
        else
          super
        end
      end
    end

    class ToRuby < Psych::Visitors::ToRuby
      unless respond_to?(:create)
        def self.create
          new
        end
      end

      def accept(target)
        super.tap do |value|
          register(target, value) if value.class.include?(Singleton)
        end
      end

      def visit_Psych_Nodes_Mapping(object) # rubocop:disable Metrics/CyclomaticComplexity, Naming/MethodName, Metrics/PerceivedComplexity
        klass = Psych.load_tags[object.tag]
        if klass
          # Implementation changed here https://github.com/ruby/psych/commit/2c644e184192975b261a81f486a04defa3172b3f
          # load_tags used to have class values, now the values are strings
          klass = resolve_class(klass) if klass.is_a?(String)
          return revive(klass, object)
        end

        case object.tag
          when %r{^!ruby/object}
            result = super
            if jruby_is_seriously_borked && result.is_a?(ActiveRecord::Base)
              klass = result.class
              id = result[klass.primary_key]
              begin
                klass.unscoped.find(id)
              rescue ActiveRecord::RecordNotFound => e
                raise Delayed::DeserializationError, "ActiveRecord::RecordNotFound, class: #{klass}, primary key: #{id} (#{e.message})"
              end
            else
              result
            end
          when %r{^!ruby/ActiveRecord:(.+)$}
            klass = resolve_class(Regexp.last_match[1])
            payload = Hash[*object.children.map { |c| accept c }]
            id = payload['attributes'][klass.primary_key]
            id = id.value if defined?(ActiveRecord::Attribute) && id.is_a?(ActiveRecord::Attribute)
            begin
              klass.unscoped.find(id)
            rescue ActiveRecord::RecordNotFound => e
              raise Delayed::DeserializationError, "ActiveRecord::RecordNotFound, class: #{klass}, primary key: #{id} (#{e.message})"
            end
          when %r{^!ruby/Mongoid:(.+)$}
            klass = resolve_class(Regexp.last_match[1])
            payload = Hash[*object.children.map { |c| accept c }]
            id = payload['attributes']['_id']
            begin
              klass.find(id)
            rescue Mongoid::Errors::DocumentNotFound => e
              raise Delayed::DeserializationError, "Mongoid::Errors::DocumentNotFound, class: #{klass}, primary key: #{id} (#{e.message})"
            end
          when %r{^!ruby/DataMapper:(.+)$}
            klass = resolve_class(Regexp.last_match[1])
            payload = Hash[*object.children.map { |c| accept c }]
            begin
              primary_keys = klass.properties.select(&:key?)
              key_names = primary_keys.map { |p| p.name.to_s }
              klass.get!(*key_names.map { |k| payload['attributes'][k] })
            rescue DataMapper::ObjectNotFoundError => e
              raise Delayed::DeserializationError, "DataMapper::ObjectNotFoundError, class: #{klass} (#{e.message})"
            end
          else
            super
        end
      end

      # defined? is triggering something really messed up in
      # jruby causing both the if AND else clauses to execute,
      # however if the check is run here, everything is fine
      def jruby_is_seriously_borked
        defined?(ActiveRecord::Base)
      end

      def resolve_class(klass_name)
        return nil if klass_name.blank?

        klass_name.constantize
      rescue StandardError
        super
      end

      def revive(klass, node)
        klass.include?(Singleton) ? klass.instance : super
      end
    end
  end
end
