require 'spec_helper'

describe Delayed::Lifecycle do
  let(:lifecycle) { Delayed::Lifecycle.new }
  let(:callback) { lambda {|*args|} }
  let(:arguments) { [1] }
  let(:behavior) { mock(Object, :before! => nil, :after! => nil, :inside! => nil) }
  let(:wrapped_block) { lambda{ behavior.inside! } }
   
  describe "before callbacks" do
    before(:each) do
      lifecycle.before(:execute, &callback)
    end
      
    it 'should execute before wrapped block' do        
      callback.should_receive(:call).with(*arguments).ordered
      behavior.should_receive(:inside!).ordered
      lifecycle.run_callbacks :execute, *arguments, &wrapped_block
    end
  end
  
  describe "after callbacks" do
    before(:each) do
      lifecycle.after(:execute, &callback)
    end
      
    it 'should execute after wrapped block' do        
      behavior.should_receive(:inside!).ordered
      callback.should_receive(:call).with(*arguments).ordered
      lifecycle.run_callbacks :execute, *arguments, &wrapped_block
    end
  end
  
  describe "around callbacks" do
    before(:each) do
      lifecycle.around(:execute) do |*args, &block|
        behavior.before!
        block.call(*args)
        behavior.after!
      end
    end
      
    it 'should before and after wrapped block' do       
      behavior.should_receive(:before!).ordered 
      behavior.should_receive(:inside!).ordered
      behavior.should_receive(:after!).ordered 
      lifecycle.run_callbacks :execute, *arguments, &wrapped_block
    end
    
    it "should execute multiple callbacks in order" do
      behavior.should_receive(:one).ordered
      behavior.should_receive(:two).ordered
      behavior.should_receive(:three).ordered
      
      lifecycle.around(:execute) { |*args, &block| behavior.one; block.call(*args) }
      lifecycle.around(:execute) { |*args, &block| behavior.two; block.call(*args) }
      lifecycle.around(:execute) { |*args, &block| behavior.three; block.call(*args) }
      
      lifecycle.run_callbacks(:execute, *arguments, &wrapped_block)
    end
  end
  
  it "should raise if callback is executed with wrong number of parameters" do
    lifecycle.before(:execute, &callback)
    expect { lifecycle.run_callbacks(:execute, 1,2,3) {} }.to raise_error(ArgumentError, /1 parameter/)
  end
  
  # # This is a spectacularly crappy way to test callbacks. What's a better way?
  # describe 'arguments callbacks' do 
  #   subject do
  #     class Testarguments < Delayed::arguments
  #       def before_execute; end
  #       def before_loop; end
  #       def before_perform; end
  #       
  #       set_callback :execute, :before, :before_execute
  #       set_callback :loop, :before, :before_loop
  #       set_callback :perform, :before, :before_perform
  #     end
  #     
  #     Testarguments.new.tap { |w| w.stop }
  #   end
  #   
  #   it "should trigger for execute event" do
  #     subject.should_receive(:before_execute).with()
  #     subject.start
  #   end
  # 
  #   it "should trigger for loop event" do
  #     subject.should_receive(:before_loop).with()
  #     subject.start
  #   end
  #   
  #   it "should trigger for perform event" do
  #     "foo".delay.length
  #     subject.should_receive(:before_perform).with()
  #     subject.start
  #   end
  # end
  # 
  # describe 'job callbacks' do 
  #   it "should trigger for enqueue event" do
  #     pending 'figure out how to test this'
  #   end
  # end
  
end