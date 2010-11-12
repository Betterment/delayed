class ActiveRecord::Base
  def to_delayed_yaml( opts = {} )
    YAML::quick_emit( self, opts ) do |out|
      out.map("tag:delayed_job.com,2010:ActiveRecord:#{self.class.name}", to_yaml_style) do |map|
        map.add('id', id)
      end
    end
  end
end

YAML.add_domain_type('delayed_job.com,2010', 'ActiveRecord') do |tag, value|
  begin
    type, model = YAML.read_type_class(tag, Kernel)
    model.find(value['id'])
  rescue ActiveRecord::RecordNotFound
    raise Delayed::DeserializationError
  end
end
