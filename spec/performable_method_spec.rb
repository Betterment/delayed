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
  end

  it "should raise a ArgumentError if target method doesn't exist" do
    lambda {
      Delayed::PerformableMethod.new(Object, :method_that_does_not_exist, [])
    }.should raise_error(NoMethodError)
  end
end
