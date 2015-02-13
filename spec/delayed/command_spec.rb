require 'helper'
require 'delayed/command'

describe Delayed::Command do

  let(:options) { [] }
  let(:logger) { double("Logger")}

  subject { Delayed::Command.new options }

  before do
    allow(Delayed::Worker).to receive(:after_fork)
    allow(Dir).to receive(:chdir)
    allow(Logger).to receive(:new).and_return(logger)
    allow_any_instance_of(Delayed::Worker).to receive(:start)
    Delayed::Worker.logger = nil
  end

  shared_examples_for "uses --log-dir option" do
    context "when --log-dir is specified" do

      let(:options) { ["--log-dir=/custom/log/dir"] }

      it "creates the delayed_job.log in the specified directory" do
        expect(Logger).to receive(:new).with("/custom/log/dir/delayed_job.log")
        subject.run
      end

    end
  end

  describe "run" do

    context "when Rails is defined" do
      let(:rails_root) { Pathname.new '/rails/root' }
      let(:rails) { double("Rails", root: rails_root)}

      before do
        stub_const("Rails", rails)
      end

      it "runs the Delayed::Worker process in Rails.root" do
        expect(Dir).to receive(:chdir).with(rails_root)
        subject.run
      end

      it "sets the Delayed::Worker logger" do
        subject.run
        expect(Delayed::Worker.logger).to be logger
      end

      context "when --log-dir is not defined" do

        it "creates the delayed_job.log in Rails.root/log" do
          expect(Logger).to receive(:new).with("/rails/root/log/delayed_job.log")
          subject.run
        end

      end

      include_examples "uses --log-dir option"

    end

    context "when Rails is not defined" do

      before do
        hide_const("Rails")
      end

      it "runs the Delayed::Worker process in $PWD" do
        expect(Dir).to receive(:chdir).with(Delayed::Command::DIR_PWD)
        subject.run
      end

      it "sets the Delayed::Worker logger" do
        subject.run
        expect(Delayed::Worker.logger).to be logger
      end

      include_examples "uses --log-dir option"

      context "when --log-dir is not specified" do
        it "creates the delayed_job.log in $PWD/log" do
          expect(Logger).to receive(:new).with("#{Delayed::Command::DIR_PWD}/log/delayed_job.log")
          subject.run
        end
      end
    end

  end

  describe 'parsing --pool argument' do
    it 'should parse --pool correctly' do
      command = Delayed::Command.new(['--pool=*:1', '--pool=test_queue:4', '--pool=mailers,misc:2'])

      expect(command.worker_pools).to eq [
        [[], 1],
        [['test_queue'], 4],
        [%w[mailers misc], 2]
      ]
    end

    it 'should allow * or blank to specify any pools' do
      command = Delayed::Command.new(['--pool=*:4'])
      expect(command.worker_pools).to eq [
        [[], 4],
      ]

      command = Delayed::Command.new(['--pool=:4'])
      expect(command.worker_pools).to eq [
        [[], 4],
      ]
    end

    it 'should default to one worker if not specified' do
      command = Delayed::Command.new(['--pool=mailers'])
      expect(command.worker_pools).to eq [
        [['mailers'], 1],
      ]
    end
  end

  describe 'running worker pools defined by multiple --pool arguments' do
    it 'should run the correct worker processes' do
      command = Delayed::Command.new(['--pool=*:1', '--pool=test_queue:4', '--pool=mailers,misc:2'])

      expect(Dir).to receive(:mkdir).with('./tmp/pids').once

      [
        ['delayed_job.0', {:quiet => true, :pid_dir => './tmp/pids', :log_dir => './log', :queues => []}],
        ['delayed_job.1', {:quiet => true, :pid_dir => './tmp/pids', :log_dir => './log', :queues => ['test_queue']}],
        ['delayed_job.2', {:quiet => true, :pid_dir => './tmp/pids', :log_dir => './log', :queues => ['test_queue']}],
        ['delayed_job.3', {:quiet => true, :pid_dir => './tmp/pids', :log_dir => './log', :queues => ['test_queue']}],
        ['delayed_job.4', {:quiet => true, :pid_dir => './tmp/pids', :log_dir => './log', :queues => ['test_queue']}],
        ['delayed_job.5', {:quiet => true, :pid_dir => './tmp/pids', :log_dir => './log', :queues => %w[mailers misc]}],
        ['delayed_job.6', {:quiet => true, :pid_dir => './tmp/pids', :log_dir => './log', :queues => %w[mailers misc]}]
      ].each do |args|
        expect(command).to receive(:run_process).with(*args).once
      end

      command.daemonize
    end
  end
end

