class ActiveRecord::Base
  yaml_as "tag:ruby.yaml.org,2002:ActiveRecord"

  def self.yaml_new(klass, tag, val)
    if ActiveRecord::VERSION::MAJOR == 3
      klass.unscoped.find(val['attributes'][klass.primary_key])
    else # Rails 2
      klass.with_exclusive_scope { klass.find(val['attributes'][klass.primary_key]) }
    end
  rescue ActiveRecord::RecordNotFound
    raise Delayed::DeserializationError
  end

  def to_yaml_properties
    ['@attributes']
  end
end

class Module
  yaml_as "tag:ruby.yaml.org,2002:module"

  def self.yaml_new(klass, tag, val)
    val.constantize
  end

  def to_yaml(options = {})
    YAML.quick_emit(nil, options) do |out|
      out.scalar(taguri, name, :plain)
    end
  end

  def yaml_tag_read_class(name)
    # Constantize the object so that ActiveSupport can attempt
    # its auto loading magic. Will raise LoadError if not successful.
    name.constantize
    name
  end
end

class Class
  yaml_as "tag:ruby.yaml.org,2002:class"
  remove_method :to_yaml if respond_to?(:to_yaml) && method(:to_yaml).owner == Class # use Module's to_yaml
end

class Struct
  def self.yaml_tag_read_class(name)
    # Constantize the object so that ActiveSupport can attempt
    # its auto loading magic. Will raise LoadError if not successful.
    name.constantize
    "Struct::#{ name }"
  end
end
