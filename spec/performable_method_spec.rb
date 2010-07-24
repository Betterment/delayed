require 'spec_helper'

describe Delayed::PerformableMethod do
  describe "perform" do
    before do
      @method = Delayed::PerformableMethod.new("foo", :count, ['o'])
    end
    
    context "with the persisted record cannot be found" do
      before do
        @method.object = nil
      end
    
      it "should be a no-op if object is nil" do
        lambda { @method.perform }.should_not raise_error
      end
    end
    
    it "should call the method on the object" do
      @method.object.should_receive(:count).with('o')
      @method.perform
    end
    
    it "should respond to on_permanent_failure when implemented and target object is called via object.delay.do_something" do
      @method = Delayed::PerformableMethod.new(OnPermanentFailureJob.new, :perform, [])
      @method.respond_to?(:on_permanent_failure).should be_true
      @method.object.should_receive(:on_permanent_failure)
      @method.on_permanent_failure
    end    
  end

  it "should raise a NoMethodError if target method doesn't exist" do
    lambda {
      Delayed::PerformableMethod.new(Object, :method_that_does_not_exist, [])
    }.should raise_error(NoMethodError)
  end
  
  it "should not raise NoMethodError if target method is private" do
    clazz = Class.new do
      def private_method
      end
      private :private_method
    end
    lambda {
      Delayed::PerformableMethod.new(clazz.new, :private_method, [])
    }.should_not raise_error(NoMethodError)
  end
end
