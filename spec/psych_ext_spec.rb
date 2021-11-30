require 'helper'
require 'active_support/core_ext/string/strip'

describe 'Psych::Visitors::ToRuby', if: defined?(Psych::Visitors::ToRuby) do
  context BigDecimal do
    it 'deserializes correctly' do
      deserialized = YAML.load_dj("--- !ruby/object:BigDecimal 18:0.1337E2\n...\n")

      expect(deserialized).to be_an_instance_of(BigDecimal)
      expect(deserialized).to eq(BigDecimal('13.37'))
    end
  end

  context Delayed::PerformableMethod do
    it 'serializes with object, method_name, args, and kwargs' do
      Delayed::PerformableMethod.new(String, :new, ['hello'], capacity: 20).tap do |pm|
        serialized = YAML.dump_dj(pm)
        expect(serialized).to eq <<~YAML
          --- !ruby/object:Delayed::PerformableMethod
          object: !ruby/class 'String'
          method_name: :new
          args:
          - hello
          kwargs:
            :capacity: 20
        YAML

        deserialized = YAML.load_dj(serialized)
        expect(deserialized).to be_an_instance_of(Delayed::PerformableMethod)
        expect(deserialized.object).to eq String
        expect(deserialized.method_name).to eq :new
        expect(deserialized.args).to eq ['hello']
        expect(deserialized.kwargs).to eq(capacity: 20)
      end
    end
  end

  context ActiveRecord::Base do
    it 'serializes and deserializes in a version-independent way' do
      Story.create.tap do |story|
        serialized = YAML.dump_dj(story)
        expect(serialized).to eq <<-YAML.strip_heredoc
          --- !ruby/ActiveRecord:Story
          attributes:
            story_id: #{story.id}
        YAML

        deserialized = YAML.load_dj(serialized)
        expect(deserialized).to be_an_instance_of(Story)
        expect(deserialized).to eq Story.find(story.id)
      end
    end

    it 'ignores garbage when deserializing' do
      Story.create.tap do |story|
        serialized = <<-YML.strip_heredoc
          --- !ruby/ActiveRecord:Story
          attributes:
            story_id: #{story.id}
            other_stuff: 'boo'
            asdf: { fish: true }
        YML

        deserialized = YAML.load_dj(serialized)
        expect(deserialized).to be_an_instance_of(Story)
        expect(deserialized).to eq Story.find(story.id)
      end
    end
  end

  context Singleton do
    it 'serializes and deserializes generic singleton classes' do
      serialized = <<-YML.strip_heredoc
        - !ruby/object:SingletonClass {}
        - !ruby/object:SingletonClass {}
      YML
      deserialized = YAML.load_dj(
        YAML.load_dj(serialized).to_yaml,
      )

      expect(deserialized).to contain_exactly(SingletonClass.instance, SingletonClass.instance)
    end

    it 'deserializes ActiveModel::NullMutationTracker' do
      serialized = <<-YML.strip_heredoc
        - !ruby/object:ActiveModel::NullMutationTracker {}
        - !ruby/object:ActiveModel::NullMutationTracker {}
      YML
      deserialized = YAML.load_dj(
        YAML.load_dj(serialized).to_yaml,
      )

      expect(deserialized).to contain_exactly(ActiveModel::NullMutationTracker.instance, ActiveModel::NullMutationTracker.instance)
    end
  end

  context 'load_tag handling' do
    # This only broadly works in ruby 2.0 but will cleanly work through load_dj
    # here because this class is so simple it only touches our extention
    YAML.load_tags['!ruby/object:RenamedClass'] = SimpleJob
    # This is how ruby 2.1 and newer works throughout the yaml handling
    YAML.load_tags['!ruby/object:RenamedString'] = 'SimpleJob'

    it 'deserializes class tag' do
      deserialized = YAML.load_dj("--- !ruby/object:RenamedClass\ncheck: 12\n")

      expect(deserialized).to be_an_instance_of(SimpleJob)
      expect(deserialized.instance_variable_get(:@check)).to eq(12)
    end

    it 'deserializes string tag' do
      deserialized = YAML.load_dj("--- !ruby/object:RenamedString\ncheck: 12\n")

      expect(deserialized).to be_an_instance_of(SimpleJob)
      expect(deserialized.instance_variable_get(:@check)).to eq(12)
    end
  end
end
