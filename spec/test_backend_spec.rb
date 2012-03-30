require 'spec_helper'

describe Delayed::Backend::Test::Job do
  it_should_behave_like 'a delayed_job backend'

  describe "#reload" do
    it 'should cause the payload object to be reloaded' do
      job = "foo".delay.length
      o = job.payload_object
      o.object_id.should_not == job.reload.payload_object.object_id
    end
  end
end
