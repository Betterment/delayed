Gem::Specification.new do |spec|
  spec.authors        = ['Nathan Griffith', 'Rowan McDonald', 'Cyrus Eslami', 'John Mileham', 'Brandon Keepers', 'Brian Ryckbost',
                         'Chris Gaffney', 'David Genord II', 'Erik Michaels-Ober', 'Matt Griffin', 'Steve Richert', 'Tobias Lütke']
  spec.description    = <<~MSG
    `Delayed` is a multi-threaded, database-backed queue used at Betterment to process millions of background jobs per day.

    It supports **postgres** and **mysql**, and is designed for use within ActiveRecord transactions, allowing jobs to be enqueued co-transactionally alongside other persistence operations.

    This gem is a hard fork of both `delayed_job` and `delayed_job_active_record` and is API-compatible with ActiveJob's `:delayed_job` queue adapter.
  MSG
  spec.email          = ['nathan@betterment.com']
  spec.files          = %w(CHANGELOG.md CONTRIBUTING.md LICENSE.md README.md Rakefile delayed.gemspec)
  spec.files          += Dir.glob('{contrib,lib,recipes,spec}/**/*') # rubocop:disable Layout/SpaceAroundOperators
  spec.homepage       = 'http://github.com/betterment/delayed'
  spec.licenses       = ['MIT']
  spec.name           = 'delayed'
  spec.require_paths  = ['lib']
  spec.summary        = 'Database-backed asynchronous priority queue system -- extracted from Shopify, forked by Betterment'
  spec.test_files     = Dir.glob('spec/**/*')

  spec.version        = '0.1.0'
  spec.metadata       = {
    'changelog_uri' => 'https://github.com/betterment/delayed/blob/main/CHANGELOG.md',
    'bug_tracker_uri' => 'https://github.com/betterment/delayed/issues',
    'source_code_uri' => 'https://github.com/betterment/delayed',
  }
  spec.required_ruby_version = '>= 2.6'

  spec.add_dependency 'activerecord', '>= 5.2'
  spec.add_dependency 'concurrent-ruby'

  spec.add_development_dependency 'actionmailer'
  spec.add_development_dependency 'activejob'
  spec.add_development_dependency 'activerecord'
  spec.add_development_dependency 'appraisal'
  spec.add_development_dependency 'betterlint'
  spec.add_development_dependency 'mysql2'
  spec.add_development_dependency 'pg'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'sqlite3'
  spec.add_development_dependency 'timecop'
end
