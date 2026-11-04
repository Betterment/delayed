# frozen_string_literal: true

# Compares the two MySQL pickup strategies under concurrent workers:
#
#   read_ahead:  reserve_with_scope_using_optimized_mysql (MySQL < 8.0.1)
#   skip_locked: reserve_with_scope_using_mysql_skip_locked (MySQL 8.0.1+)
#
# Each run enqueues JOBS jobs, forks WORKERS processes that reserve and then
# delete their claimed jobs until the queue is empty, and reports drain time,
# throughput, reserve latency, and how many reserve calls came back empty while
# jobs were still available.
#
# Usage (needs a MySQL server matching spec/database.yml; THIS DROPS AND
# RECREATES the delayed_jobs table in that database):
#
#   ADAPTER=mysql2 bundle exec ruby -Ilib -Ispec benchmarks/mysql_reserve.rb
#
# Tunables: JOBS (default 20000), WORKERS (default "4,16,32"), RUNS (default 3),
# MAX_CLAIMS (default 5), READ_AHEAD (default 5).

require 'erb'
require 'json'
require 'yaml'
require 'active_job'
require 'active_record'
require 'delayed'

Delayed.logger = Logger.new(nil)
ActiveRecord::Base.default_timezone = :utc if ActiveRecord::Base.respond_to?(:default_timezone=)
ActiveRecord.default_timezone = :utc if ActiveRecord.respond_to?(:default_timezone=)

DB_CONFIG = YAML.safe_load(ERB.new(File.read('spec/database.yml')).result).fetch('mysql2')
JOBS = Integer(ENV.fetch('JOBS', 20_000))
WORKER_COUNTS = ENV.fetch('WORKERS', '4,16,32').split(',').map { |n| Integer(n) }
RUNS = Integer(ENV.fetch('RUNS', 3))
MAX_CLAIMS = Integer(ENV.fetch('MAX_CLAIMS', 5))
READ_AHEAD = Integer(ENV.fetch('READ_AHEAD', 5))
STRATEGIES = {
  'read_ahead' => :reserve_with_scope_using_optimized_mysql,
  'skip_locked' => :reserve_with_scope_using_mysql_skip_locked,
}.freeze

ActiveRecord::Base.establish_connection(DB_CONFIG)
ActiveRecord::Migration.verbose = false
Dir['db/migrate/*.rb'].each { |f| require_relative("../#{f}") }
ActiveRecord::Base.connection.drop_table(:delayed_jobs, if_exists: true)
[CreateDelayedJobs, AddNameToDelayedJobs, AddIndexToDelayedJobsName, IndexLiveJobs,
  IndexFailedJobs, RemoveLegacyIndex].each { |m| m.migrate(:up) }
Delayed::Job.reset_column_information

abort 'This server does not support SKIP LOCKED' unless Delayed::Job.mysql_skip_locked_supported?
puts "MySQL #{Delayed::Job.connection.select_value('SELECT VERSION()')}, jobs=#{JOBS}, " \
     "max_claims=#{MAX_CLAIMS}, read_ahead=#{READ_AHEAD}, runs=#{RUNS}"

def seed!
  Delayed::Job.delete_all
  now = Time.now.utc - 60
  rows = Array.new(JOBS) do |i|
    { priority: i % 10, attempts: 0, handler: "--- !ruby/object:SimpleJob {}\n", queue: 'default',
      name: 'SimpleJob', run_at: now, created_at: now, updated_at: now }
  end
  rows.each_slice(2_000) { |slice| Delayed::Job.insert_all(slice) }
end

def work(strategy, index)
  ActiveRecord::Base.establish_connection(DB_CONFIG)
  worker = Delayed::Worker.new
  worker.name = "bench-#{index}"
  stats = { claimed: [], empty: 0, errors: 0, latencies: [] }
  loop do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    jobs = begin
      Delayed::Job.public_send(strategy, Delayed::Job.claimable_by(worker), worker, Delayed::Job.db_time_now)
    rescue ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout
      stats[:errors] += 1
      next
    end
    stats[:latencies] << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)

    if jobs.empty?
      break unless Delayed::Job.exists?

      stats[:empty] += 1
      next
    end

    ids = jobs.map(&:id)
    stats[:claimed].concat(ids)
    Delayed::Job.where(id: ids).delete_all # stand-in for running + destroying the job
  end
  stats
end

def run_once(strategy, workers)
  seed!
  ActiveRecord::Base.connection_handler.clear_all_connections!
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  pipes = Array.new(workers) do |i|
    reader, writer = IO.pipe
    fork do
      reader.close
      writer.write(JSON.dump(work(strategy, i)))
      writer.close
      exit!(0)
    end
    writer.close
    reader
  end
  results = pipes.map { |r| JSON.parse(r.read).tap { r.close } }
  Process.waitall
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  ActiveRecord::Base.establish_connection(DB_CONFIG)

  claimed = results.flat_map { |r| r['claimed'] }
  latencies = results.flat_map { |r| r['latencies'] }.sort
  {
    seconds: elapsed,
    jobs_per_sec: claimed.size / elapsed,
    duplicates: claimed.size - claimed.uniq.size,
    missing: JOBS - claimed.uniq.size,
    reserves: latencies.size,
    empty_pct: 100.0 * results.sum { |r| r['empty'] } / latencies.size,
    errors: results.sum { |r| r['errors'] },
    p50_ms: latencies[latencies.size / 2] * 1000,
    p99_ms: latencies[(latencies.size * 0.99).floor] * 1000,
  }
end

def median(values)
  values.sort[values.size / 2]
end

Delayed::Worker.max_claims = MAX_CLAIMS
Delayed::Worker.read_ahead = READ_AHEAD

def print_row(*cols)
  puts cols.each_with_index.map { |col, i| i.zero? ? col.to_s.ljust(12) : col.to_s.rjust(9) }.join(' ')
end

print_row('strategy', 'workers', 'drain_s', 'jobs/s', 'p50_ms', 'p99_ms', 'reserves', 'empty%', 'dupes', 'errors')
WORKER_COUNTS.each do |workers|
  STRATEGIES.each do |label, strategy|
    runs = Array.new(RUNS) { run_once(strategy, workers) }
    raise "#{label}: #{runs.sum { |r| r[:missing] }} jobs never claimed" if runs.any? { |r| r[:missing].positive? }

    m = ->(key) { median(runs.map { |r| r[key] }) }
    print_row(label, workers, m.call(:seconds).round(2), m.call(:jobs_per_sec).round, m.call(:p50_ms).round(2),
      m.call(:p99_ms).round(2), m.call(:reserves), "#{m.call(:empty_pct).round(1)}%",
      runs.sum { |r| r[:duplicates] }, runs.sum { |r| r[:errors] })
  end
end
