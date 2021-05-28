require 'logger'
require 'rspec'
require 'timecop'

require 'action_mailer'
require 'active_job'
require 'active_record'

require 'delayed'
require 'delayed/backend/shared_example'

if ENV['DEBUG_LOGS']
  Delayed::Worker.logger = Logger.new($stdout)
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
    Delayed::Job.delete_all
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# Add this directory so the ActiveSupport autoloading works
ActiveSupport::Dependencies.autoload_paths << File.dirname(__FILE__)

RSpec::Matchers.define :emit_notification do |expected_event_name|
  attr_reader :actual, :expected

  def supports_block_expectations?
    true
  end

  chain :with_payload, :expected_payload
  diffable

  match do |block|
    @expected = { event_name: expected_event_name, payload: expected_payload }
    @actuals = []
    callback = ->(name, _started, _finished, _unique_id, payload) do
      @actuals << { event_name: name, payload: payload }
    end

    ActiveSupport::Notifications.subscribed(callback, expected_event_name, &block)

    unless expected_payload
      @actuals.each { |a| a.delete(:payload) }
      @expected.delete(:payload)
    end

    @actual = @actuals.find { |a| values_match?(@expected, a) } || @actuals.last
    values_match?(@expected, @actual)
  end

  failure_message do
    <<~MSG
      Expected the code block to emit:
        #{@expected.inspect}
      But instead, the following were emitted:
        #{@actuals.map(&:inspect).join("\n  ")}
    MSG
  end
end

def current_adapter
  ENV.fetch('ADAPTER', 'sqlite3')
end

def current_database
  if current_adapter == 'sqlite3'
    a_string_ending_with('tmp/database.sqlite')
  else
    'delayed_job_test'
  end
end
