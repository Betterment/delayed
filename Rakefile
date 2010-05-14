# -*- encoding: utf-8 -*-
begin
  require 'jeweler'
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install jeweler"
  exit 1
end

Jeweler::Tasks.new do |s|
  s.name     = "delayed_job"
  s.summary  = "Database-backed asynchronous priority queue system -- Extracted from Shopify"
  s.email    = "tobi@leetsoft.com"
  s.homepage = "http://github.com/collectiveidea/delayed_job"
  s.description = "Delayed_job (or DJ) encapsulates the common pattern of asynchronously executing longer tasks in the background. It is a direct extraction from Shopify where the job table is responsible for a multitude of core tasks.\n\nThis gem is collectiveidea's fork (http://github.com/collectiveidea/delayed_job)."
  s.authors  = ["Brandon Keepers", "Tobias Lütke"]
  
  s.has_rdoc = true
  s.rdoc_options = ["--main", "README.textile", "--inline-source", "--line-numbers"]
  s.extra_rdoc_files = ["README.textile"]
  
  s.test_files = Dir['spec/*_spec.rb']
  
  s.add_dependency "daemons"
  s.add_development_dependency "rspec"
  s.add_development_dependency "sqlite3-ruby"
  s.add_development_dependency "activerecord"
  s.add_development_dependency "mongo_mapper"
  s.add_development_dependency "dm-core"
  s.add_development_dependency "dm-observer"
  s.add_development_dependency "dm-aggregates"
  s.add_development_dependency "dm-validations"
  s.add_development_dependency "do_sqlite3"
  s.add_development_dependency "couchrest"
end

require 'spec/rake/spectask'


task :default do
  %w(2.3.5 3.0.0.beta3).each do |version|
    puts "Running specs with Rails #{version}"
    system("RAILS_VERSION=#{version} rake -s spec;")
  end
end

desc 'Run the specs'
Spec::Rake::SpecTask.new(:spec) do |t|
  t.libs << 'lib'
  t.pattern = 'spec/*_spec.rb'
  t.verbose = true
end
task :spec => :check_dependencies

