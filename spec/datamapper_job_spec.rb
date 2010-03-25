require 'spec_helper'

require 'delayed/backend/data_mapper'

DataMapper.logger = ActiveRecord::Base.logger
DataMapper.setup(:default, "sqlite3::memory:")

describe Delayed::Backend::DataMapper::Job do
  before(:all) do
    @backend = Delayed::Backend::DataMapper::Job
  end
  
  before(:each) do
    # reset database before each example is run
    DataMapper.auto_migrate!
  end
  
  it_should_behave_like 'a backend'
end
