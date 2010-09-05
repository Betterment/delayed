# -*- encoding: utf-8 -*-
require 'rubygems'
require 'bundler/setup'

require 'spec/rake/spectask'
desc 'Run the specs'
Spec::Rake::SpecTask.new(:spec) do |t|
  t.libs << 'lib'
  t.pattern = 'spec/*_spec.rb'
  t.verbose = true
end

task :default => :spec
