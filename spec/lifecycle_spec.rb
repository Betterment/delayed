require 'helper'

describe Delayed::Lifecycle do
  let(:lifecycle) { described_class.new }
  let(:callback) { lambda { |*_args| } }
  let(:arguments) { [1] }
  let(:behavior) { double(Object, before!: nil, after!: nil, inside!: nil) }
  let(:wrapped_block) { proc { behavior.inside! } }

  describe 'before callbacks' do
    before(:each) do
      lifecycle.before(:enqueue, &callback)
    end

    it 'enqueues before wrapped block' do
      expect(callback).to receive(:call).with(*arguments).ordered
      expect(behavior).to receive(:inside!).ordered
      lifecycle.run_callbacks :enqueue, *arguments, &wrapped_block
    end
  end

  describe 'after callbacks' do
    before(:each) do
      lifecycle.after(:enqueue, &callback)
    end

    it 'enqueues after wrapped block' do
      expect(behavior).to receive(:inside!).ordered
      expect(callback).to receive(:call).with(*arguments).ordered
      lifecycle.run_callbacks :enqueue, *arguments, &wrapped_block
    end
  end

  describe 'around callbacks' do
    before(:each) do
      lifecycle.around(:enqueue) do |*args, &block|
        behavior.before!
        block.call(*args)
        behavior.after!
      end
    end

    it 'wraps a block' do
      expect(behavior).to receive(:before!).ordered
      expect(behavior).to receive(:inside!).ordered
      expect(behavior).to receive(:after!).ordered
      lifecycle.run_callbacks :enqueue, *arguments, &wrapped_block
    end

    it 'enqueues multiple callbacks in order' do
      expect(behavior).to receive(:one).ordered
      expect(behavior).to receive(:two).ordered
      expect(behavior).to receive(:three).ordered

      lifecycle.around(:enqueue) do |*args, &block|
        behavior.one
        block.call(*args)
      end
      lifecycle.around(:enqueue) do |*args, &block|
        behavior.two
        block.call(*args)
      end
      lifecycle.around(:enqueue) do |*args, &block|
        behavior.three
        block.call(*args)
      end
      lifecycle.run_callbacks(:enqueue, *arguments, &wrapped_block)
    end
  end

  it 'raises if callback is enqueued with wrong number of parameters' do
    lifecycle.before(:enqueue, &callback)
    expect {
      lifecycle.run_callbacks(:enqueue, 1, 2, 3) {} # no-op
    }.to raise_error(ArgumentError, /1 parameter/)
  end
end
