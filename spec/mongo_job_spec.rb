require 'spec_helper'

require 'delayed/backend/mongo'

MongoMapper.connection = Mongo::Connection.new nil, nil, :logger => ActiveRecord::Base.logger
MongoMapper.database = 'delayed_job'

describe Delayed::Backend::Mongo::Job do
  before(:all) do
    @backend = Delayed::Backend::Mongo::Job
  end
  
  before(:each) do
    MongoMapper.database.collections.each(&:remove)
  end
  
  it_should_behave_like 'a backend'
end