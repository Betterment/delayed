require 'yaml'

class Module
  yaml_as "tag:ruby.yaml.org,2002:module"

  def Module.yaml_new( klass, tag, val )
    if String === val
      val.split(/::/).inject(Object) {|m, n| m.const_get(n)}
    else
      raise YAML::TypeError, "Invalid Module: " + val.inspect
    end
  end

  def to_yaml( opts = {} )
    YAML::quick_emit( nil, opts ) { |out|
      out.scalar( "tag:ruby.yaml.org,2002:module", self.name, :plain )
    }
  end
end

class Class
  yaml_as "tag:ruby.yaml.org,2002:class"

  def Class.yaml_new( klass, tag, val )
    if String === val
      val.split(/::/).inject(Object) {|m, n| m.const_get(n)}
    else
      raise YAML::TypeError, "Invalid Class: " + val.inspect
    end
  end

  def to_yaml( opts = {} )
    YAML::quick_emit( nil, opts ) { |out|
      out.scalar( "tag:ruby.yaml.org,2002:class", self.name, :plain )
    }
  end
end
