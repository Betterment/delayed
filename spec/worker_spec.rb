require 'spec_helper'

describe Delayed::Worker do
  describe "backend=" do
    before do
      @clazz = Class.new
      Delayed::Worker.backend = @clazz
    end

    it "sets the Delayed::Job constant to the backend" do
      expect(Delayed::Job).to eq(@clazz)
    end

    it "sets backend with a symbol" do
      Delayed::Worker.backend = :test
      expect(Delayed::Worker.backend).to eq(Delayed::Backend::Test::Job)
    end
  end
end
