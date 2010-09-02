require 'spec_helper'
require 'backend/shared_backend_spec'
require 'delayed/backend/mongoid'

describe Delayed::Backend::Mongoid::Job do
  before(:all) do
    @backend = Delayed::Backend::Mongoid::Job
    Delayed::Worker.backend = :mongoid
  end
  
  before(:each) do
    Delayed::Backend::Mongoid::Job.destroy_all
  end
  
  it_should_behave_like 'a backend'
  
  
  describe "before_fork" do
    after do
      ::Mongoid.master.connection.close
    end
    
    it "should disconnect" do
      lambda do
        Delayed::Backend::Mongoid::Job.before_fork
      end.should change { !!Mongoid.master.connection.connected? }.from(true).to(false)
    end
  end

  describe "after_fork" do
    before do
      ::Mongoid.master.connection.close
    end
    
    it "should call reconnect" do
      lambda do
        Delayed::Backend::Mongoid::Job.after_fork
      end.should change { !!Mongoid.master.connection.connected? }.from(false).to(true)
    end
  end
end