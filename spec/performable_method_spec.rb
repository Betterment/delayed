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

      it "does nothing if object is nil" do
        expect{@method.perform}.not_to raise_error
      end
    end

    it "calls the method on the object" do
      @method.object.should_receive(:count).with('o')
      @method.perform
    end
  end

  it "raises a NoMethodError if target method doesn't exist" do
    expect {
      Delayed::PerformableMethod.new(Object, :method_that_does_not_exist, [])
    }.to raise_error(NoMethodError)
  end

  it "does not raise NoMethodError if target method is private" do
    clazz = Class.new do
      def private_method
      end
      private :private_method
    end
    expect {
      Delayed::PerformableMethod.new(clazz.new, :private_method, [])
    }.not_to raise_error(NoMethodError)
  end

  describe "hooks" do
    %w(enqueue before after success).each do |hook|
      it "delegates #{hook} hook to object" do
        story = Story.create
        story.should_receive(hook).with(an_instance_of(Delayed::Job))
        story.delay.tell.invoke_job
      end
    end

    %w(before after success).each do |hook|
      it "delegates #{hook} hook to object when delay_jobs = false" do
        Delayed::Worker.delay_jobs = false
        story = Story.create
        story.should_receive(hook).with(an_instance_of(Delayed::Job))
        story.delay.tell
      end
    end

    it "delegates error hook to object" do
      story = Story.create
      story.should_receive(:error).with(an_instance_of(Delayed::Job), an_instance_of(RuntimeError))
      story.should_receive(:tell).and_raise(RuntimeError)
      expect{story.delay.tell.invoke_job}.to raise_error
    end

    it "delegates error hook to object when delay_jobs = false" do
      Delayed::Worker.delay_jobs = false
      story = Story.create
      story.should_receive(:error).with(an_instance_of(Delayed::Job), an_instance_of(RuntimeError))
      story.should_receive(:tell).and_raise(RuntimeError)
      expect{story.delay.tell}.to raise_error
    end

    it "delegates failure hook to object" do
      method = Delayed::PerformableMethod.new("object", :size, [])
      method.object.should_receive(:failure)
      method.failure
    end

    it "delegates failure hook to object when delay_jobs = false" do
      Delayed::Worker.delay_jobs = false
      method = Delayed::PerformableMethod.new("object", :size, [])
      method.object.should_receive(:failure)
      method.failure
    end

  end
end
