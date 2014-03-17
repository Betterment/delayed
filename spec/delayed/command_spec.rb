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
end