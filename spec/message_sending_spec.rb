require 'spec_helper'

describe Delayed::MessageSending do
  describe "handle_asynchronously" do
    class Story < ActiveRecord::Base
      def tell!(arg)
      end
      handle_asynchronously :tell!
    end
    
    it "should alias original method" do
      Story.new.should respond_to(:tell_without_delay!)
      Story.new.should respond_to(:tell_with_delay!)
    end
    
    it "should create a PerformableMethod" do
      story = Story.create!
      lambda {
        job = story.tell!(1)
        job.payload_object.class.should   == Delayed::PerformableMethod
        job.payload_object.method.should  == :tell_without_delay!
        job.payload_object.args.should    == [1]
      }.should change { Delayed::Job.count }
    end
  end

  context "delay" do
    it "should create a new PerformableMethod job" do
      lambda {
        job = "hello".delay.count('l')
        job.payload_object.class.should   == Delayed::PerformableMethod
        job.payload_object.method.should  == :count
        job.payload_object.args.should    == ['l']
      }.should change { Delayed::Job.count }.by(1)
    end
  
    it "should set job options" do
      run_at = Time.parse('2010-05-03 12:55 AM')
      job = Object.delay(:priority => 20, :run_at => run_at).to_s
      job.run_at.should == run_at
      job.priority.should == 20
    end
  end
end
