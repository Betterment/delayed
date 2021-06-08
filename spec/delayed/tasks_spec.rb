require 'helper'

describe 'rake' do
  let(:runnable) { instance_double(Delayed::Runnable, start: true) }

  before do
    Rake::Task.clear
    Rake::Task.define_task(:environment)
    load 'lib/delayed/tasks.rb'

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:key).and_call_original
  end

  def stub_env(key, value)
    allow(ENV).to receive(:[]).with(key).and_return(value)
    allow(ENV).to receive(:key?).with(key).and_return(true)
  end

  describe 'delayed:work' do
    before do
      allow(Delayed::Worker).to receive(:new).and_return(runnable)
    end

    it 'starts a worker' do
      Rake.application.invoke_task 'delayed:work'
      expect(runnable).to have_received(:start)
    end

    context 'when environment variables are set' do
      before do
        stub_env('MIN_PRIORITY', '6')
        stub_env('MAX_PRIORITY', '8')
        stub_env('QUEUES', 'foo,bar')
        stub_env('SLEEP_DELAY', '1')
        stub_env('READ_AHEAD', '3')
        stub_env('MAX_CLAIMS', '3')
      end

      it 'sets the worker config' do
        expect { Rake.application.invoke_task('delayed:work') }
          .to change { Delayed::Worker.min_priority }.from(nil).to(6)
          .and change { Delayed::Worker.max_priority }.from(nil).to(8)
          .and change { Delayed::Worker.queues }.from([]).to(%w(foo bar))
          .and change { Delayed::Worker.sleep_delay }.from(5).to(1)
          .and change { Delayed::Worker.read_ahead }.from(5).to(3)
          .and change { Delayed::Worker.max_claims }.from(5).to(3)
      end
    end
  end

  describe 'delayed:monitor' do
    before do
      allow(Delayed::Monitor).to receive(:new).and_return(runnable)
    end

    it 'starts a monitor' do
      Rake.application.invoke_task 'delayed:monitor'
      expect(runnable).to have_received(:start)
    end

    context 'when environment variables are set' do
      before do
        stub_env('MIN_PRIORITY', '6')
        stub_env('MAX_PRIORITY', '8')
        stub_env('QUEUES', 'foo,bar')
        stub_env('SLEEP_DELAY', '1')
        stub_env('READ_AHEAD', '3')
        stub_env('MAX_CLAIMS', '3')
      end

      it 'sets the worker config' do
        expect { Rake.application.invoke_task('delayed:monitor') }
          .to change { Delayed::Worker.min_priority }.from(nil).to(6)
          .and change { Delayed::Worker.max_priority }.from(nil).to(8)
          .and change { Delayed::Worker.queues }.from([]).to(%w(foo bar))
          .and change { Delayed::Worker.sleep_delay }.from(5).to(1)
          .and change { Delayed::Worker.read_ahead }.from(5).to(3)
          .and change { Delayed::Worker.max_claims }.from(5).to(3)
      end
    end
  end

  describe 'jobs:work' do
    before do
      allow(Delayed::Worker).to receive(:new).and_return(runnable)
    end

    it 'starts a worker' do
      Rake.application.invoke_task 'jobs:work'
      expect(runnable).to have_received(:start)
    end
  end
end
