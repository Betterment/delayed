Gem::Specification.new do |spec|
  spec.authors        = ['Nathan Griffith', 'Rowan McDonald', 'Cyrus Eslami', 'John Mileham', 'Brandon Keepers', 'Brian Ryckbost',
                         'Chris Gaffney', 'David Genord II', 'Erik Michaels-Ober', 'Matt Griffin', 'Steve Richert', 'Tobias Lütke']
  spec.description    = <<~MSG
    Delayed is a multi-threaded, SQL-driven ActiveJob backend used at Betterment to process millions
    of background jobs per day. It supports postgres, mysql, and sqlite, and is designed to be
    Reliable (with co-transactional job enqueues and guaranteed, at-least-once execution), Scalable
    (with an optimized pickup query and concurrent job execution), Resilient (with built-in retry
    mechanisms, exponential backoff, and failed job preservation), and Maintainable (with robust
    instrumentation, continuous monitoring, and priority-based alerting).
  MSG
  spec.email          = ['nathan@betterment.com']
  spec.files          = Dir['{app,config,db,lib}/**/*', 'LICENSE', 'Rakefile', 'README.md']
  spec.test_files     = Dir['spec/**/*']
  spec.homepage       = 'http://github.com/betterment/delayed'
  spec.licenses       = ['MIT']
  spec.name           = 'delayed'
  spec.require_paths  = ['lib']
  spec.summary        = 'a multi-threaded, SQL-driven ActiveJob backend used at Betterment to process millions of background jobs per day'

  spec.version        = '0.5.5'
  spec.metadata       = {
    'changelog_uri' => 'https://github.com/betterment/delayed/blob/main/CHANGELOG.md',
    'bug_tracker_uri' => 'https://github.com/betterment/delayed/issues',
    'source_code_uri' => 'https://github.com/betterment/delayed',
    'rubygems_mfa_required' => 'true',
  }
  spec.required_ruby_version = '>= 2.6'

  spec.add_dependency 'activerecord', '>= 5.2'
  spec.add_dependency 'concurrent-ruby'
end
