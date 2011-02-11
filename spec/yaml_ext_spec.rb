require 'spec_helper'

describe YAML do
  it "should autoload classes that are unknown at runtime" do
    lambda {
      obj = YAML.load("--- !ruby/object:Autoloaded::Clazz {}")
      obj.class.to_s.should == 'Autoloaded::Clazz'
    }.should_not raise_error
  end

  it "should autoload structs that are unknown at runtime" do
    lambda {
      obj = YAML.load("--- !ruby/struct:Autoloaded::Struct {}")
      obj.class.to_s.should == 'Autoloaded::Struct'
    }.should_not raise_error
  end

  # As we're overriding some of Yaml's internals it is best that our changes
  # don't impact other places where Yaml is used. Or at least don't make it
  # look like the exception is caused by DJ
  it "should not raise exception on poorly formatted yaml" do
    lambda do
      YAML.load(<<-EOYAML
default:
  <<: *login
EOYAML
      )
    end.should_not raise_error
  end
  
end
