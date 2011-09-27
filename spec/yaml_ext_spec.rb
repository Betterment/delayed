require 'spec_helper'

describe "YAML" do
  it "should autoload classes that are unknown at runtime" do
    lambda {
      yaml = "--- !ruby/class:Autoloaded::Clazz {}\n"
      YAML.load(yaml).should == Autoloaded::Clazz
    }.should_not raise_error
  end

  it "should autoload a struct" do
    lambda {
      yaml = "--- !ruby/class:Autoloaded::Struct {}\n"
      YAML.load(yaml).should == Autoloaded::Struct
    }.should_not raise_error
  end

  it "should autoload structs that are unknown at runtime" do
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
end
