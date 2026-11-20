# frozen_string_literal: true

require 'helper'
require 'open3'

RSpec.describe Delayed::Limitable do
  describe 'Sorbet runtime compatibility' do
    it 'does not load sorbet-runtime in the test process' do
      expect(defined?(T::Sig)).to be_nil
    end

    it 'supports `sig`s on methods defined after with_limit' do
      output, status = Open3.capture2e(
        RbConfig.ruby, '-rbundler/setup', 'spec/support/sorbet_runtime/limitable_jobs.rb',
        chdir: File.expand_path('../..', __dir__)
      )
      expect(status).to be_success, output
    end
  end
end
