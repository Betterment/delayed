# frozen_string_literal: true

require 'helper'

describe Delayed do
  describe "require 'delayed'" do
    it 'loads standalone, without active_record or active_job pre-required' do
      script = <<~RUBY
        raise 'expected ActiveRecord to not be loaded yet' if defined?(ActiveRecord)
        raise 'expected ActiveJob to not be loaded yet' if defined?(ActiveJob)

        require 'delayed'

        raise 'expected ActiveJob to not be loaded' if defined?(ActiveJob)

        require 'active_job'
        ActiveJob::Base # fire the on_load(:active_job) hook

        raise 'expected DelayedAdapter to be registered' unless defined?(ActiveJob::QueueAdapters::DelayedAdapter)
      RUBY

      lib = File.expand_path('../lib', __dir__)
      expect(system(RbConfig.ruby, '-I', lib, '-e', script)).to eq(true)
    end
  end
end
