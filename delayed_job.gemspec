# -*- encoding: utf-8 -*-

Gem::Specification.new do |spec|
  spec.authors        = ['Brandon Keepers', 'Brian Ryckbost', 'Chris Gaffney', 'David Genord II', 'Erik Michaels-Ober', 'Matt Griffin', 'Steve Richert', 'Tobias Lütke']
  spec.description    = 'Delayed_job (or DJ) encapsulates the common pattern of asynchronously executing longer tasks in the background. It is a direct extraction from Shopify where the job table is responsible for a multitude of core tasks.'
  spec.email          = ['brian@collectiveidea.com']
  spec.files          = %w[CHANGELOG.md CONTRIBUTING.md LICENSE.md README.md Rakefile delayed_job.gemspec]
  spec.files          += Dir.glob('{contrib,lib,recipes,spec}/**/*') # rubocop:disable Layout/SpaceAroundOperators
  spec.homepage       = 'http://github.com/collectiveidea/delayed_job'
  spec.licenses       = ['MIT']
  spec.name           = 'delayed_job'
  spec.require_paths  = ['lib']
  spec.summary        = 'Database-backed asynchronous priority queue system -- Extracted from Shopify'
  spec.test_files     = Dir.glob('spec/**/*')

  spec.version        = '4.1.9'
  spec.metadata       = {
    'changelog_uri' => 'https://github.com/collectiveidea/delayed_job/blob/master/CHANGELOG.md',
    'bug_tracker_uri' => 'https://github.com/collectiveidea/delayed_job/issues',
    'source_code_uri' => 'https://github.com/collectiveidea/delayed_job'
  }
  spec.required_ruby_version = '>= 2.6'

  spec.add_dependency 'activesupport', '>= 5.2'

  spec.add_development_dependency 'actionmailer'
  spec.add_development_dependency 'activerecord'
  spec.add_development_dependency 'appraisal'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'sqlite3'
end
