require 'spec_helper'

describe "YAML" do
  it "should autoload classes" do
    lambda {
      yaml = "--- !ruby/class:Autoloaded::Clazz {}\n"
      YAML.load(yaml).should == Autoloaded::Clazz
    }.should_not raise_error
  end

  it "should autoload the class of a struct" do
    lambda {
      yaml = "--- !ruby/class:Autoloaded::Struct {}\n"
      YAML.load(yaml).should == Autoloaded::Struct
    }.should_not raise_error
  end

  it "should autoload the class for the instance of a struct" do
    lambda {
      yaml = "--- !ruby/struct:Autoloaded::InstanceStruct {}"
      YAML.load(yaml).class.should == Autoloaded::InstanceStruct
    }.should_not raise_error
  end

  it "should autoload the class for the instance" do
    lambda {
      yaml = "--- !ruby/object:Autoloaded::InstanceClazz {}\n"
      YAML.load(yaml).class.should == Autoloaded::InstanceClazz
    }.should_not raise_error
  end

  it "should not throw an uninitialized constant Syck::Syck when using YAML.load_file with poorly formed yaml" do
    lambda {
      YAML.load_file(File.expand_path('spec/fixtures/example.yml'))
    }.should_not raise_error
  end

  it "should not throw an uninitialized constant Syck::Syck when using YAML.load with poorly formed yaml" do
    lambda { YAML.load(YAML.dump("foo: *bar"))}.should_not raise_error
  end
end
