require 'helper'
require 'delayed/command'

describe Delayed::Command do
  describe "parsing --pools argument" do
    it "should parse --pools correctly" do
      command = Delayed::Command.new(['--pools=*:1/test_queue:4/mailers,misc:2'])

      expect(command.worker_pools).to eq [
        [ [], 1 ],
        [ ['test_queue'], 4 ],
        [ ['mailers', 'misc'], 2 ]
      ]
    end

    it "should allow * or blank for any pools" do
      command = Delayed::Command.new(['--pools=*:4'])
      expect(command.worker_pools).to eq [
        [ [], 4 ],
      ]

      command = Delayed::Command.new(['--pools=:4'])
      expect(command.worker_pools).to eq [
        [ [], 4 ],
      ]
    end
  end

  describe "running worker pools defined by --pools" do
    it "should run the correct worker processes" do
      command = Delayed::Command.new(['--pools=*:1/test_queue:4/mailers,misc:2'])

      Dir.should_receive(:mkdir).with('./tmp/pids').once

      [
        ["delayed_job.0", {:quiet=>true, :pid_dir=>"./tmp/pids", :queues=>[]}],
        ["delayed_job.1", {:quiet=>true, :pid_dir=>"./tmp/pids", :queues=>["test_queue"]}],
        ["delayed_job.2", {:quiet=>true, :pid_dir=>"./tmp/pids", :queues=>["test_queue"]}],
        ["delayed_job.3", {:quiet=>true, :pid_dir=>"./tmp/pids", :queues=>["test_queue"]}],
        ["delayed_job.4", {:quiet=>true, :pid_dir=>"./tmp/pids", :queues=>["test_queue"]}],
        ["delayed_job.5", {:quiet=>true, :pid_dir=>"./tmp/pids", :queues=>["mailers", "misc"]}],
        ["delayed_job.6", {:quiet=>true, :pid_dir=>"./tmp/pids", :queues=>["mailers", "misc"]}]
      ].each do |args|
        command.should_receive(:run_process).with(*args).once
      end

      command.daemonize
    end
  end
end
