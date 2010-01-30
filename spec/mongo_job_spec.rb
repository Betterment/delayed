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
  
  describe "delayed method" do
    class MongoStoryReader
      def read(story)
        "Epilog: #{story.tell}"
      end
    end
    
    class MongoStory
      include MongoMapper::Document
      key :text, String
      
      def tell
        text
      end
    end
    
    it "should ignore not found errors because they are permanent" do
      story = MongoStory.create :text => 'Once upon a time…'
      job = story.send_later(:tell)
      story.destroy
      lambda { job.invoke_job }.should_not raise_error
    end

    it "should store the object as string" do
      story = MongoStory.create :text => 'Once upon a time…'
      job = story.send_later(:tell)

      job.payload_object.class.should   == Delayed::PerformableMethod
      job.payload_object.object.should  == "LOAD;MongoStory;#{story.id}"
      job.payload_object.method.should  == :tell
      job.payload_object.args.should    == []
      job.payload_object.perform.should == 'Once upon a time…'
    end

    it "should store arguments as string" do
      story = MongoStory.create :text => 'Once upon a time…'
      job = MongoStoryReader.new.send_later(:read, story)
      job.payload_object.class.should   == Delayed::PerformableMethod
      job.payload_object.method.should  == :read
      job.payload_object.args.should    == ["LOAD;MongoStory;#{story.id}"]
      job.payload_object.perform.should == 'Epilog: Once upon a time…'
    end
  end
end