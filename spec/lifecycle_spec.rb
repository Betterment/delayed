require 'spec_helper'

describe Delayed::Lifecycle do
 
  # This is a spectacularly crappy way to test callbacks. What's a better way?
  describe 'worker callbacks' do 
    subject do
      class TestWorker < Delayed::Worker
        def before_execute; end
        def before_loop; end
        def before_perform; end
        
        set_callback :execute, :before, :before_execute
        set_callback :loop, :before, :before_loop
        set_callback :perform, :before, :before_perform
      end
      
      TestWorker.new.tap { |w| w.stop }
    end
    
    it "should trigger for execute event" do
      subject.should_receive(:before_execute).with()
      subject.start
    end
  
    it "should trigger for loop event" do
      subject.should_receive(:before_loop).with()
      subject.start
    end
    
    it "should trigger for perform event" do
      "foo".delay.length
      subject.should_receive(:before_perform).with()
      subject.start
    end
  end
  
  describe 'job callbacks' do 
    it "should trigger for enqueue event" do
      pending 'figure out how to test this'
    end
  end
  
end