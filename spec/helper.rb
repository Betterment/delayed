require 'rspec'
require 'timecop'

require 'action_mailer'
require 'active_job'
require 'active_record'

require 'delayed'
require 'sample_jobs'

require 'rake'

if ENV['DEBUG_LOGS']
  Delayed.logger = Logger.new($stdout)
else
  require 'tempfile'

  tf = Tempfile.new('dj.log')
  Delayed.logger = Logger.new(tf.path)
  tf.unlink
end
ENV['RAILS_ENV'] = 'test'

db_adapter = ENV["ADAPTER"]
gemfile = ENV["BUNDLE_GEMFILE"]
db_adapter ||= gemfile && gemfile[%r{gemfiles/(.*?)/}] && $1 # rubocop:disable Style/PerlBackrefs
db_adapter ||= "sqlite3"

config = YAML.load(ERB.new(File.read("spec/database.yml")).result)
ActiveRecord::Base.establish_connection config[db_adapter]
ActiveRecord::Base.logger = Delayed.logger
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

migration_template = File.open("lib/generators/delayed/templates/migration.rb")

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
  config.around(:each) do |example|
    aj_priority_was = ActiveJob::Base.priority
    aj_queue_name_was = ActiveJob::Base.queue_name
    default_priority_was = Delayed::Worker.default_priority
    default_queue_name_was = Delayed::Worker.default_queue_name
    delay_jobs_was = Delayed::Worker.delay_jobs
    destroy_failed_jobs_was = Delayed::Worker.destroy_failed_jobs
    max_attempts_was = Delayed::Worker.max_attempts
    max_claims_was = Delayed::Worker.max_claims
    max_priority_was = Delayed::Worker.max_priority
    max_run_time_was = Delayed::Worker.max_run_time
    min_priority_was = Delayed::Worker.min_priority
    queues_was = Delayed::Worker.queues
    read_ahead_was = Delayed::Worker.read_ahead
    sleep_delay_was = Delayed::Worker.sleep_delay

    example.run
  ensure
    ActiveJob::Base.priority = aj_priority_was
    ActiveJob::Base.queue_name = aj_queue_name_was
    Delayed::Worker.default_priority = default_priority_was
    Delayed::Worker.default_queue_name = default_queue_name_was
    Delayed::Worker.delay_jobs = delay_jobs_was
    Delayed::Worker.destroy_failed_jobs = destroy_failed_jobs_was
    Delayed::Worker.max_attempts = max_attempts_was
    Delayed::Worker.max_claims = max_claims_was
    Delayed::Worker.max_priority = max_priority_was
    Delayed::Worker.max_run_time = max_run_time_was
    Delayed::Worker.min_priority = min_priority_was
    Delayed::Worker.queues = queues_was
    Delayed::Worker.read_ahead = read_ahead_was
    Delayed::Worker.sleep_delay = sleep_delay_was

    Delayed::Job.delete_all
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

if ActiveRecord::VERSION::MAJOR >= 7
  require "zeitwerk"
  loader = Zeitwerk::Loader.new
  loader.push_dir File.dirname(__FILE__)
  loader.setup
else
  # Add this directory so the ActiveSupport autoloading works
  ActiveSupport::Dependencies.autoload_paths << File.dirname(__FILE__)
end

RSpec::Matchers.define :emit_notification do |expected_event_name|
  attr_reader :actual, :expected

  def supports_block_expectations?
    true
  end

  chain :with_payload, :expected_payload
  chain :with_value, :expected_value
  diffable

  match do |block|
    @expected = { event_name: expected_event_name, payload: expected_payload, value: expected_value }
    @actuals = []
    callback = ->(name, _started, _finished, _unique_id, payload) do
      @actuals << { event_name: name, payload: payload.except(:value), value: payload[:value] }
    end

    ActiveSupport::Notifications.subscribed(callback, expected_event_name, &block)

    unless expected_payload
      @actuals.each { |a| a.delete(:payload) }
      @expected.delete(:payload)
    end

    @actual = @actuals.select { |a| values_match?(@expected.except(:value), a.except(:value)) }
    @expected = [@expected]
    values_match?(@expected, @actual)
  end

  failure_message do
    <<~MSG
      Expected the code block to emit:
        #{@expected.first.inspect}

      But instead, the following were emitted:
        #{(@actual.presence || @actuals).map(&:inspect).join("\n  ")}
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
