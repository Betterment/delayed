module Psych
  module Visitors
    class YAMLTree
      def visit_Class(klass)
        tag = ['!ruby/class', klass.name].compact.join(':')
        register(klass, @emitter.start_mapping(nil, tag, false, Nodes::Mapping::BLOCK))
        @emitter.end_mapping
      end
    end

    class ToRuby
      def visit_Psych_Nodes_Mapping_with_class(object)
        return revive(Psych.load_tags[object.tag], object) if Psych.load_tags[object.tag]

        case object.tag
        when /^!ruby\/class:?(.*)?$/
          resolve_class $1
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

