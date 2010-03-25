MongoMapper.connection = Mongo::Connection.new nil, nil, :logger => DELAYED_JOB_LOGGER
MongoMapper.database = 'delayed_job'

unless defined?(Story)
  class Story
    include ::MongoMapper::Document
    def tell; text; end       
    def whatever(n, _); tell*n; end
    def self.count; end
    
    handle_asynchronously :whatever
  end
end
