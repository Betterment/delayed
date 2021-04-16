require 'logger'
require 'rspec'

require 'action_mailer'
require 'active_record'

require 'delayed_job'
require 'delayed_job_active_record'
require 'delayed/backend/shared_spec'

if ENV['DEBUG_LOGS']
  Delayed::Worker.logger = Logger.new(STDOUT)
else
  require 'tempfile'

  tf = Tempfile.new('dj.log')
  Delayed::Worker.logger = Logger.new(tf.path)
  tf.unlink
end
ENV['RAILS_ENV'] = 'test'

db_adapter = ENV["ADAPTER"]
gemfile = ENV["BUNDLE_GEMFILE"]
db_adapter ||= gemfile && gemfile[%r{gemfiles/(.*?)/}] && $1 # rubocop:disable Style/PerlBackrefs
db_adapter ||= "sqlite3"

module Rails
  def self.root
    '.'
  end
end

config = YAML.load(ERB.new(File.read("spec/database.yml")).result)
ActiveRecord::Base.establish_connection config[db_adapter]
ActiveRecord::Base.logger = Delayed::Worker.logger
ActiveRecord::Migration.verbose = false

# MySQL 5.7 no longer supports null default values for the primary key
# Override the default primary key type in Rails <= 4.0
# https://stackoverflow.com/a/34555109
if db_adapter == "mysql2"
  types = if defined?(ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter)
    # ActiveRecord 3.2+
    ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter::NATIVE_DATABASE_TYPES
  else
    # ActiveRecord < 3.2
    ActiveRecord::ConnectionAdapters::Mysql2Adapter::NATIVE_DATABASE_TYPES
  end
  types[:primary_key] = types[:primary_key].sub(" DEFAULT NULL", "")
end

migration_template = File.open("lib/generators/delayed_job/templates/migration.rb")

# need to eval the template with the migration_version intact
migration_context =
  Class.new do
    def my_binding
      binding
    end

    private

    def migration_version
      "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]" if ActiveRecord::VERSION::MAJOR >= 5
    end
  end

migration_ruby = ERB.new(migration_template.read).result(migration_context.new.my_binding)
eval(migration_ruby) # rubocop:disable Security/Eval

ActiveRecord::Schema.define do
  if table_exists?(:delayed_jobs)
    # `if_exists: true` was only added in Rails 5
    drop_table :delayed_jobs
  end

  CreateDelayedJobs.up

  create_table :stories, primary_key: :story_id, force: true do |table|
    table.string :text
    table.boolean :scoped, default: true
  end
end

class Story < ActiveRecord::Base
  self.primary_key = :story_id

  def tell
    text
  end

  def whatever(number)
    tell * number
  end
  default_scope { where(scoped: true) }

  handle_asynchronously :whatever
end

class SingletonClass
  include Singleton
end

RSpec.configure do |config|
  config.after(:each) do
    Delayed::Worker.reset
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# Add this directory so the ActiveSupport autoloading works
ActiveSupport::Dependencies.autoload_paths << File.dirname(__FILE__)
