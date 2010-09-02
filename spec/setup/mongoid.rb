require 'mongoid'

require 'delayed/backend/mongoid'

Mongoid.configure do |config|
  config.master = config.master = Mongo::Connection.new.db('dl_spec') 
end

class Story
  include ::Mongoid::Document
  def tell; text; end       
  def whatever(n, _); tell*n; end
  def self.count; end

  handle_asynchronously :whatever
end

