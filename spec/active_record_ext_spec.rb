require 'spec_helper'

describe ActiveRecord do
  it 'should load classes with non-default primary key' do
    lambda {
      YAML.load(Story.create.to_yaml)
    }.should_not raise_error    
  end
end