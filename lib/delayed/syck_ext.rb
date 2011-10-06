class Module
  yaml_as "tag:ruby.yaml.org,2002:module"

  def self.yaml_new(klass, tag, val)
    klass
  end

  def to_yaml(options = {})
    YAML.quick_emit(nil, options) do |out|
      out.scalar(taguri, name, :plain)
    end
  end

  def yaml_tag_read_class(name)
    # Constantize the object so that ActiveSupport can attempt
    # its auto loading magic. Will raise LoadError if not successful.
    #
    # When requiring yaml, the parsers redefine the YAML constant. This causes an
    # issue with poorly formatted yaml, specifically in the case of a Bad Alias.
    # When you'd expect to see Syck::BadAlias, the name we're getting is
    # YAML::Syck::BadAlias and trying to constantize this results in an uninitialized constant Syck::Syck.
    name.gsub(/^YAML::/, '').constantize
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
