require 'rspec'
require 'timecop'

require 'action_mailer'
require 'active_job'
require 'active_record'

require 'delayed'
require 'sample_jobs'

require 'rake'

require 'snapshot_testing/rspec'

ActiveSupport.on_load(:active_record) do
  require 'global_id/identification'
  include GlobalID::Identification
  GlobalID.app = 'test'
end

if ActiveSupport.gem_version >= Gem::Version.new('7.1')
  frameworks = [ActiveModel, ActiveRecord, ActionMailer, ActiveJob, ActiveSupport]
  frameworks.each { |framework| framework.deprecator.behavior = :raise }
else
  ActiveSupport::Deprecation.behavior = :raise
end

Delayed.logger = Logger.new($stdout)
Delayed.logger.level = ENV['DEBUG_LOGS'] ? Logger::DEBUG : Logger::FATAL

def with_log_level(level)
  logger_level_was = Delayed.logger.level
  Delayed.logger.level = level
  yield
ensure
  Delayed.logger.level = logger_level_was
end

ENV['RAILS_ENV'] = 'test'

def current_adapter
  ENV.fetch('ADAPTER', 'sqlite3')
end

config = YAML.load(ERB.new(File.read("spec/database.yml")).result)
ActiveRecord::Base.establish_connection config[current_adapter]
ActiveRecord::Base.logger = Delayed.logger
ActiveJob::Base.logger = Delayed.logger
ActiveRecord::Migration.verbose = false

if ActiveRecord.respond_to?(:default_timezone=)
  ActiveRecord.default_timezone = :utc
else
  ActiveRecord::Base.default_timezone = :utc
end

# MySQL 5.7 no longer supports null default values for the primary key
# Override the default primary key type in Rails <= 4.0
# https://stackoverflow.com/a/34555109
if current_adapter == "mysql2"
  types = if defined?(ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter)
            # ActiveRecord 3.2+
            ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter::NATIVE_DATABASE_TYPES
          else
            # ActiveRecord < 3.2
            ActiveRecord::ConnectionAdapters::Mysql2Adapter::NATIVE_DATABASE_TYPES
          end
  types[:primary_key] = types[:primary_key].sub(" DEFAULT NULL", "")
end

Dir['db/migrate/*.rb'].each { |f| require_relative("../#{f}") }

ActiveRecord::Schema.define do
  if ActiveRecord::VERSION::MAJOR >= 7
    drop_table :delayed_jobs, if_exists: true
  elsif ActiveRecord::Base.connection.table_exists?(:delayed_jobs)
    drop_table :delayed_jobs
  end

  # Let's prove reversibility when we set up our test DB:
  def run_migration(klass)
    klass.migrate(:up)
    klass.migrate(:down)
    klass.migrate(:up)
  end

  with_log_level(Logger::WARN) do
    run_migration(CreateDelayedJobs)
    run_migration(AddNameToDelayedJobs)
    run_migration(AddIndexToDelayedJobsName)
    run_migration(IndexLiveJobs)
    run_migration(IndexFailedJobs)
    run_migration(SetPostgresFillfactor)
    run_migration(RemoveLegacyIndex)

    # Test that these index migrations can be re-applied idempotently.
    # (In case identical indexes had been manually applied previously.)
    AddIndexToDelayedJobsName.migrate(:up)
    IndexLiveJobs.migrate(:up)
    IndexFailedJobs.migrate(:up)
    RemoveLegacyIndex.migrate(:up)
  end

  create_table :stories, primary_key: :story_id, force: true do |table|
    table.string :text
    table.boolean :scoped, default: true
  end
end

Delayed::Job.reset_column_information

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

# Negative values are treated as sleep(0),
# so we can use different values to test the sleep behavior:
TEST_MIN_RESERVE_INTERVAL = -10
TEST_SLEEP_DELAY = -100

RSpec.configure do |config|
  config.include SnapshotTesting::RSpec

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
    min_reserve_interval_was = Delayed::Worker.min_reserve_interval
    plugins_was = Delayed.plugins.dup

    Delayed::Worker.sleep_delay = TEST_SLEEP_DELAY
    Delayed::Worker.min_reserve_interval = TEST_MIN_RESERVE_INTERVAL

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
    Delayed::Worker.min_reserve_interval = min_reserve_interval_was
    Delayed.plugins = plugins_was

    Delayed::Job.delete_all
  end

  config.around(:each, :with_legacy_table_index) do |example|
    IndexFailedJobs.migrate(:down)
    IndexLiveJobs.migrate(:down)
    AddIndexToDelayedJobsName.migrate(:down)
    RemoveLegacyIndex.migrate(:down)
    example.run
  ensure
    RemoveLegacyIndex.migrate(:up)
    AddIndexToDelayedJobsName.migrate(:up)
    IndexLiveJobs.migrate(:up)
    IndexFailedJobs.migrate(:up)
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

def default_timezone=(zone)
  if ActiveRecord::VERSION::MAJOR >= 7
    ActiveRecord.default_timezone = zone
  else
    ActiveRecord::Base.default_timezone = zone
  end
end

RSpec::Matchers.define :emit_notification do |expected_event_name|
  attr_reader :actual, :expected

  def supports_block_expectations?
    true
  end

  chain :with_payload, :expected_payload
  chain :with_value, :expected_value
  chain(:approximately) { @approximately = true }
  diffable

  match do |block|
    if @approximately && current_adapter != 'postgresql'
      @expected_value = a_value_within([2, @expected_value.abs * 0.05].max).of(@expected_value)
    end

    @expected = { event_name: expected_event_name, payload: expected_payload, value: @expected_value }
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

def current_database
  if current_adapter == 'sqlite3'
    a_string_ending_with('tmp/database.sqlite')
  else
    'delayed_job_test'
  end
end

QueryUnderTest = Struct.new(:sql, :connection) do
  def self.for(query, connection: ActiveRecord::Base.connection)
    new(query.respond_to?(:to_sql) ? query.to_sql : query.to_s, connection)
  end

  def full_description
    [formatted, explain].join("\n\n")
  end

  def formatted
    fmt = sql.squish

    if ActiveRecord::VERSION::MAJOR < 7
      # Rails 6.0->6.1 optimizes for fewer "OR" parenthesis
      fmt.gsub!(/\(\((.+ OR .+)\)( OR .+)\)/) { "(#{Regexp.last_match(1)}#{Regexp.last_match(2)})" }
    end

    # basic formatting for easier git diffing
    fmt.gsub(/ (SELECT|FROM|WHERE|GROUP BY|ORDER BY) /) { "\n  #{Regexp.last_match(1).strip} " }
      .gsub(/ (AND|OR) /) { "\n    #{Regexp.last_match(1).strip} " }
      # normalize and truncate 'AS' names/aliases (changes across Rails versions)
      .gsub(/AS ("|`)?(\w+)("|`)?/) { "AS #{Regexp.last_match(2)[0...63]}" }
      # newline and indent when aliased columns are listed
      .gsub(/AS (\w+),/) { "AS #{Regexp.last_match(1)},\n      " }
      # remove quotes around column names in aggregate functions
      .gsub(/(MIN|MAX|COUNT|SUM)\(("|`)(\w+)("|`)\)/) { "#{Regexp.last_match(1)}(#{Regexp.last_match(3)})" }
  end

  def explain
    send(:"#{current_adapter}_explain").strip
      # normalize plan estimates
      .gsub(/\(cost=.+\)/, '(cost=...)')
  end

  private

  def postgresql_explain
    connection.execute("SET seq_page_cost = 100")
    connection.execute("SET enable_hashagg = off")
    connection.execute("SET plan_cache_mode TO force_generic_plan")
    connection.execute("EXPLAIN (VERBOSE) #{sql}").values.flatten.join("\n")
  ensure
    connection.execute("RESET plan_cache_mode")
    connection.execute("RESET enable_hashagg")
    connection.execute("RESET seq_page_cost")
  end

  def mysql2_explain
    seed_rows! if Delayed::Job.none? # MySQL needs a bit of data to reach for indexes
    connection.execute("ANALYZE TABLE #{Delayed::Job.table_name}")
    connection.execute("SET SESSION max_seeks_for_key = 1")
    connection.execute("EXPLAIN FORMAT=TREE #{sql}").to_a.map(&:first).join("\n")
  ensure
    connection.execute("SET SESSION max_seeks_for_key = DEFAULT")
  end

  def sqlite3_explain
    connection.execute("EXPLAIN QUERY PLAN #{sql}").flat_map { |r| r["detail"] }.join("\n")
  end

  def seed_rows!
    now = Delayed::Job.db_time_now
    100.times do
      [true, false].repeated_combination(5).each_with_index do |(erroring, failed, locked, future), i|
        Delayed::Job.create!(
          run_at: now + (future ? i.minutes : -i.minutes),
          queue: "queue_#{i}",
          handler: "--- !ruby/object:SimpleJob\n",
          attempts: erroring ? i : 0,
          failed_at: failed ? now - i.minutes : nil,
          locked_at: locked ? now - i.seconds : nil,
        )
      end
    end
  end
end
