require 'helper'

describe Delayed::PerformableMethod do
  describe 'perform' do
    let(:test_class) do
      Class.new do
        cattr_accessor :result

        def foo(arg, kwarg:)
          self.class.result = [arg, kwarg]
        end
      end
    end

    before do
      @method = described_class.new(test_class.new, :foo, ['a'], { kwarg: 'b' })
    end

    context 'with the persisted record cannot be found' do
      before do
        @method.object = nil
      end

      it 'does nothing if object is nil' do
        expect { @method.perform }.not_to raise_error
      end
    end

    it 'calls the method on the object' do
      expect { @method.perform }
        .to change { test_class.result }
        .from(nil).to %w(a b)
    end

    if RUBY_VERSION < '3.0'
      context 'when kwargs are nil (job was delayed via prior gem version)' do
        before do
          @method = described_class.new(test_class.new, :foo, ['a', { kwarg: 'b' }], nil)
        end

        it 'calls the method on the object' do
          expect { @method.perform }
            .to change { test_class.result }
            .from(nil).to %w(a b)
        end
      end
    end
  end

  it "raises a NoMethodError if target method doesn't exist" do
    expect {
      described_class.new(Object, :method_that_does_not_exist, [], {})
    }.to raise_error(NoMethodError)
  end

  it 'does not raise NoMethodError if target method is private' do
    clazz = Class.new do
      def private_method; end
      private :private_method
    end
    expect { described_class.new(clazz.new, :private_method, [], {}) }.not_to raise_error
  end

  context 'when it receives an object that is not persisted' do
    let(:object) { double(persisted?: false, expensive_operation: true) }

    it 'raises an ArgumentError' do
      expect { described_class.new(object, :expensive_operation, [], {}) }.to raise_error ArgumentError
    end

    it 'does not raise ArgumentError if the object acts like a Her model' do
      allow(object.class).to receive(:save_existing).and_return(true)
      expect { described_class.new(object, :expensive_operation, [], {}) }.not_to raise_error
    end
  end

  describe 'display_name' do
    it 'returns class_name#method_name for instance methods' do
      expect(described_class.new('foo', :count, ['o'], {}).display_name).to eq('String#count')
    end

    it 'returns class_name.method_name for class methods' do
      expect(described_class.new(Class, :inspect, [], {}).display_name).to eq('Class.inspect')
    end
  end

  describe 'hooks' do
    %w(before after success).each do |hook|
      it "delegates #{hook} hook to object" do
        story = Story.create
        job = story.delay.tell

        expect(story).to receive(hook).with(job)
        job.invoke_job
      end
    end

    it 'delegates enqueue hook to object' do
      story = Story.create
      expect(story).to receive(:enqueue).with(an_instance_of(Delayed::Job))
      story.delay.tell
    end

    it 'delegates error hook to object' do
      story = Story.create
      expect(story).to receive(:error).with(an_instance_of(Delayed::Job), an_instance_of(RuntimeError))
      expect(story).to receive(:tell).and_raise(RuntimeError)
      expect { story.delay.tell.invoke_job }.to raise_error(RuntimeError)
    end

    it 'delegates failure hook to object' do
      method = described_class.new('object', :size, [], {})
      expect(method.object).to receive(:failure)
      method.failure
    end

    context 'with delay_job == false' do
      before do
        Delayed::Worker.delay_jobs = false
      end

      after do
        Delayed::Worker.delay_jobs = true
      end

      %w(before after success).each do |hook|
        it "delegates #{hook} hook to object" do
          story = Story.create
          expect(story).to receive(hook).with(an_instance_of(Delayed::Job))
          story.delay.tell
        end
      end

      it 'delegates error hook to object' do
        story = Story.create
        expect(story).to receive(:error).with(an_instance_of(Delayed::Job), an_instance_of(RuntimeError))
        expect(story).to receive(:tell).and_raise(RuntimeError)
        expect { story.delay.tell }.to raise_error(RuntimeError)
      end

      it 'delegates failure hook to object' do
        method = described_class.new('object', :size, [], {})
        expect(method.object).to receive(:failure)
        method.failure
      end
    end
  end
end
