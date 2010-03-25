require 'spec_helper'

require 'delayed/backend/datamapper'

DataMapper.logger = ActiveRecord::Base.logger
DataMapper.setup(:default, "sqlite3::memory:")

module Delayed
  module Backend
    module DataMapper
      class Job
        def self.find id
          get id
        end
        
        def update_attributes(attributes)
          self.update attributes
          self.save
        end
      end
    end
  end
end

describe Delayed::Backend::DataMapper::Job do
  before(:all) do
    @backend = Delayed::Backend::DataMapper::Job
  end
  
  before(:each) do
    # reset database before each example is run
    DataMapper.auto_migrate!
  end
  
  it_should_behave_like 'a backend'
  
  describe "delayed method" do
    class DMStoryReader
      def read(story)
        "Epilog: #{story.tell}"
      end
    end
    
    class DMStory
      include DataMapper::Resource
      property :id,   Serial
      property :text, String
      
      def tell
        text
      end
    end
  end
end
