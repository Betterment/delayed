require 'helper'

RSpec.describe Delayed::Monitor do
  before do
    described_class.sleep_delay = 0
  end

  let(:default_payload) do
    {
      table: 'delayed_jobs',
      database: current_database,
      database_adapter: current_adapter,
      queue: 'default',
    }
  end

  it 'emits empty metrics for all default priorities' do
    expect { subject.run! }
      .to emit_notification("delayed.monitor.run").with_payload(default_payload.except(:queue))
      .and emit_notification("delayed.job.count").with_payload(default_payload.merge(priority: 'interactive')).with_value(0)
      .and emit_notification("delayed.job.count").with_payload(default_payload.merge(priority: 'user_visible')).with_value(0)
      .and emit_notification("delayed.job.count").with_payload(default_payload.merge(priority: 'eventual')).with_value(0)
      .and emit_notification("delayed.job.count").with_payload(default_payload.merge(priority: 'reporting')).with_value(0)
      .and emit_notification("delayed.job.future_count").with_payload(default_payload.merge(priority: 'interactive')).with_value(0)
      .and emit_notification("delayed.job.future_count").with_payload(default_payload.merge(priority: 'user_visible')).with_value(0)
      .and emit_notification("delayed.job.future_count").with_payload(default_payload.merge(priority: 'eventual')).with_value(0)
      .and emit_notification("delayed.job.future_count").with_payload(default_payload.merge(priority: 'reporting')).with_value(0)
      .and emit_notification("delayed.job.locked_count").with_payload(default_payload.merge(priority: 'interactive')).with_value(0)
      .and emit_notification("delayed.job.locked_count").with_payload(default_payload.merge(priority: 'user_visible')).with_value(0)
      .and emit_notification("delayed.job.locked_count").with_payload(default_payload.merge(priority: 'eventual')).with_value(0)
      .and emit_notification("delayed.job.locked_count").with_payload(default_payload.merge(priority: 'reporting')).with_value(0)
      .and emit_notification("delayed.job.erroring_count").with_payload(default_payload.merge(priority: 'interactive')).with_value(0)
      .and emit_notification("delayed.job.erroring_count").with_payload(default_payload.merge(priority: 'user_visible')).with_value(0)
      .and emit_notification("delayed.job.erroring_count").with_payload(default_payload.merge(priority: 'eventual')).with_value(0)
      .and emit_notification("delayed.job.erroring_count").with_payload(default_payload.merge(priority: 'reporting')).with_value(0)
      .and emit_notification("delayed.job.failed_count").with_payload(default_payload.merge(priority: 'interactive')).with_value(0)
      .and emit_notification("delayed.job.failed_count").with_payload(default_payload.merge(priority: 'user_visible')).with_value(0)
      .and emit_notification("delayed.job.failed_count").with_payload(default_payload.merge(priority: 'eventual')).with_value(0)
      .and emit_notification("delayed.job.failed_count").with_payload(default_payload.merge(priority: 'reporting')).with_value(0)
      .and emit_notification("delayed.job.working_count").with_payload(default_payload.merge(priority: 'interactive')).with_value(0)
      .and emit_notification("delayed.job.working_count").with_payload(default_payload.merge(priority: 'user_visible')).with_value(0)
      .and emit_notification("delayed.job.working_count").with_payload(default_payload.merge(priority: 'eventual')).with_value(0)
      .and emit_notification("delayed.job.working_count").with_payload(default_payload.merge(priority: 'reporting')).with_value(0)
      .and emit_notification("delayed.job.workable_count").with_payload(default_payload.merge(priority: 'interactive')).with_value(0)
      .and emit_notification("delayed.job.workable_count").with_payload(default_payload.merge(priority: 'user_visible')).with_value(0)
      .and emit_notification("delayed.job.workable_count").with_payload(default_payload.merge(priority: 'eventual')).with_value(0)
      .and emit_notification("delayed.job.workable_count").with_payload(default_payload.merge(priority: 'reporting')).with_value(0)
      .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'interactive')).with_value(0)
      .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'user_visible')).with_value(0)
      .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'eventual')).with_value(0)
      .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'reporting')).with_value(0)
      .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'interactive')).with_value(0)
      .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'user_visible')).with_value(0)
      .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'eventual')).with_value(0)
      .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'reporting')).with_value(0)
      .and emit_notification("delayed.job.alert_age_percent").with_payload(default_payload.merge(priority: 'interactive')).with_value(0)
      .and emit_notification("delayed.job.alert_age_percent").with_payload(default_payload.merge(priority: 'user_visible')).with_value(0)
      .and emit_notification("delayed.job.alert_age_percent").with_payload(default_payload.merge(priority: 'eventual')).with_value(0)
      .and emit_notification("delayed.job.alert_age_percent").with_payload(default_payload.merge(priority: 'reporting')).with_value(0)
  end

  context 'when named priorities are customized' do
    around do |example|
      Delayed::Priority.names = { high: 0, low: 7 }
      example.run
    ensure
      Delayed::Priority.names = nil
    end

    it 'emits empty metrics for all custom priorities' do
      expect { subject.run! }
        .to emit_notification("delayed.monitor.run").with_payload(default_payload.except(:queue))
        .and emit_notification("delayed.job.count").with_payload(default_payload.merge(priority: 'high')).with_value(0)
        .and emit_notification("delayed.job.count").with_payload(default_payload.merge(priority: 'low')).with_value(0)
        .and emit_notification("delayed.job.future_count").with_payload(default_payload.merge(priority: 'high')).with_value(0)
        .and emit_notification("delayed.job.future_count").with_payload(default_payload.merge(priority: 'low')).with_value(0)
        .and emit_notification("delayed.job.locked_count").with_payload(default_payload.merge(priority: 'high')).with_value(0)
        .and emit_notification("delayed.job.locked_count").with_payload(default_payload.merge(priority: 'low')).with_value(0)
        .and emit_notification("delayed.job.erroring_count").with_payload(default_payload.merge(priority: 'high')).with_value(0)
        .and emit_notification("delayed.job.erroring_count").with_payload(default_payload.merge(priority: 'low')).with_value(0)
        .and emit_notification("delayed.job.failed_count").with_payload(default_payload.merge(priority: 'high')).with_value(0)
        .and emit_notification("delayed.job.failed_count").with_payload(default_payload.merge(priority: 'low')).with_value(0)
        .and emit_notification("delayed.job.working_count").with_payload(default_payload.merge(priority: 'high')).with_value(0)
        .and emit_notification("delayed.job.working_count").with_payload(default_payload.merge(priority: 'low')).with_value(0)
        .and emit_notification("delayed.job.workable_count").with_payload(default_payload.merge(priority: 'high')).with_value(0)
        .and emit_notification("delayed.job.workable_count").with_payload(default_payload.merge(priority: 'low')).with_value(0)
        .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'high')).with_value(0)
        .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'low')).with_value(0)
        .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'high')).with_value(0)
        .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'low')).with_value(0)
        .and emit_notification("delayed.job.alert_age_percent").with_payload(default_payload.merge(priority: 'high')).with_value(0)
        .and emit_notification("delayed.job.alert_age_percent").with_payload(default_payload.merge(priority: 'low')).with_value(0)
    end
  end

  context 'when there are jobs in the queue' do
    let(:now) { Time.now.change(nsec: 0) } # rubocop:disable Rails/TimeZone
    let(:job_attributes) do
      {
        run_at: now,
        queue: 'default',
        handler: "--- !ruby/object:SimpleJob\n",
        attempts: 0,
      }
    end
    let(:failed_attributes) { { run_at: now - 1.week, last_error: '123', failed_at: now - 1.day, attempts: 4, locked_at: now - 1.day } }
    let(:p0_attributes) { job_attributes.merge(priority: 1) }
    let(:p10_attributes) { job_attributes.merge(priority: 13) }
    let(:p20_attributes) { job_attributes.merge(priority: 23) }
    let(:p30_attributes) { job_attributes.merge(priority: 999) }
    let(:p0_payload) { default_payload.merge(priority: 'interactive') }
    let(:p10_payload) { default_payload.merge(priority: 'user_visible') }
    let(:p20_payload) { default_payload.merge(priority: 'eventual') }
    let(:p30_payload) { default_payload.merge(priority: 'reporting') }
    let!(:p0_workable_job) { Delayed::Job.create! p0_attributes.merge(run_at: now - 30.seconds) }
    let!(:p0_failed_job) { Delayed::Job.create! p0_attributes.merge(failed_attributes) }
    let!(:p0_future_job) { Delayed::Job.create! p0_attributes.merge(run_at: now + 1.hour) }
    let!(:p0_working_job) { Delayed::Job.create! p0_attributes.merge(locked_at: now - 3.minutes) }
    let!(:p10_workable_job) { Delayed::Job.create! p10_attributes.merge(run_at: now - 2.minutes) }
    let!(:p10_failed_job) { Delayed::Job.create! p10_attributes.merge(failed_attributes) }
    let!(:p10_future_job) { Delayed::Job.create! p10_attributes.merge(run_at: now + 1.hour) }
    let!(:p10_working_job) { Delayed::Job.create! p10_attributes.merge(locked_at: now - 7.minutes) }
    let!(:p20_workable_job) { Delayed::Job.create! p20_attributes.merge(run_at: now - 1.hour) }
    let!(:p20_failed_job) { Delayed::Job.create! p20_attributes.merge(failed_attributes) }
    let!(:p20_future_job) { Delayed::Job.create! p20_attributes.merge(run_at: now + 1.hour) }
    let!(:p20_working_job) { Delayed::Job.create! p20_attributes.merge(locked_at: now - 9.minutes) }
    let!(:p30_workable_job) { Delayed::Job.create! p30_attributes.merge(run_at: now - 6.hours) }
    let!(:p30_failed_job) { Delayed::Job.create! p30_attributes.merge(failed_attributes) }
    let!(:p30_future_job) { Delayed::Job.create! p30_attributes.merge(run_at: now + 1.hour) }
    let!(:p30_working_job) { Delayed::Job.create! p30_attributes.merge(locked_at: now - 11.minutes) }
    let!(:p30_workable_job_in_other_queue) { Delayed::Job.create! p30_attributes.merge(run_at: now - 4.hours, queue: 'banana') }

    around do |example|
      Timecop.freeze(now) { example.run }
    end

    it 'emits the expected results for each metric' do
      expect { subject.run! }
        .to emit_notification("delayed.monitor.run").with_payload(default_payload.except(:queue))
        .and emit_notification("delayed.job.count").with_payload(p0_payload).with_value(4)
        .and emit_notification("delayed.job.future_count").with_payload(p0_payload).with_value(1)
        .and emit_notification("delayed.job.locked_count").with_payload(p0_payload).with_value(2)
        .and emit_notification("delayed.job.erroring_count").with_payload(p0_payload).with_value(1)
        .and emit_notification("delayed.job.failed_count").with_payload(p0_payload).with_value(1)
        .and emit_notification("delayed.job.working_count").with_payload(p0_payload).with_value(1)
        .and emit_notification("delayed.job.workable_count").with_payload(p0_payload).with_value(1)
        .and emit_notification("delayed.job.max_age").with_payload(p0_payload).with_value(30.seconds)
        .and emit_notification("delayed.job.max_lock_age").with_payload(p0_payload).with_value(3.minutes)
        .and emit_notification("delayed.job.alert_age_percent").with_payload(p0_payload).with_value(30.0.seconds / 1.minute * 100)
        .and emit_notification("delayed.job.count").with_payload(p10_payload).with_value(4)
        .and emit_notification("delayed.job.future_count").with_payload(p10_payload).with_value(1)
        .and emit_notification("delayed.job.locked_count").with_payload(p10_payload).with_value(2)
        .and emit_notification("delayed.job.erroring_count").with_payload(p10_payload).with_value(1)
        .and emit_notification("delayed.job.failed_count").with_payload(p10_payload).with_value(1)
        .and emit_notification("delayed.job.working_count").with_payload(p10_payload).with_value(1)
        .and emit_notification("delayed.job.workable_count").with_payload(p10_payload).with_value(1)
        .and emit_notification("delayed.job.max_age").with_payload(p10_payload).with_value(2.minutes)
        .and emit_notification("delayed.job.max_lock_age").with_payload(p10_payload).with_value(7.minutes)
        .and emit_notification("delayed.job.alert_age_percent").with_payload(p10_payload).with_value(2.0.minutes / 3.minutes * 100)
        .and emit_notification("delayed.job.count").with_payload(p20_payload).with_value(4)
        .and emit_notification("delayed.job.future_count").with_payload(p20_payload).with_value(1)
        .and emit_notification("delayed.job.locked_count").with_payload(p20_payload).with_value(2)
        .and emit_notification("delayed.job.erroring_count").with_payload(p20_payload).with_value(1)
        .and emit_notification("delayed.job.failed_count").with_payload(p20_payload).with_value(1)
        .and emit_notification("delayed.job.working_count").with_payload(p20_payload).with_value(1)
        .and emit_notification("delayed.job.workable_count").with_payload(p20_payload).with_value(1)
        .and emit_notification("delayed.job.max_age").with_payload(p20_payload).with_value(1.hour)
        .and emit_notification("delayed.job.max_lock_age").with_payload(p20_payload).with_value(9.minutes)
        .and emit_notification("delayed.job.alert_age_percent").with_payload(p20_payload).with_value(1.hour / 1.5.hours * 100)
        .and emit_notification("delayed.job.count").with_payload(p30_payload).with_value(4)
        .and emit_notification("delayed.job.future_count").with_payload(p30_payload).with_value(1)
        .and emit_notification("delayed.job.locked_count").with_payload(p30_payload).with_value(2)
        .and emit_notification("delayed.job.erroring_count").with_payload(p30_payload).with_value(1)
        .and emit_notification("delayed.job.failed_count").with_payload(p30_payload).with_value(1)
        .and emit_notification("delayed.job.working_count").with_payload(p30_payload).with_value(1)
        .and emit_notification("delayed.job.workable_count").with_payload(p30_payload).with_value(1)
        .and emit_notification("delayed.job.max_age").with_payload(p30_payload).with_value(6.hours)
        .and emit_notification("delayed.job.max_lock_age").with_payload(p30_payload).with_value(11.minutes)
        .and emit_notification("delayed.job.alert_age_percent").with_payload(p30_payload).with_value(100) # 6 hours / 4 hours (overflow)
        .and emit_notification("delayed.job.workable_count").with_payload(p30_payload.merge(queue: 'banana')).with_value(1)
        .and emit_notification("delayed.job.max_age").with_payload(p30_payload.merge(queue: 'banana')).with_value(4.hours)
    end

    context 'when named priorities are customized' do
      around do |example|
        Delayed::Priority.names = { high: 0, low: 20 }
        example.run
      ensure
        Delayed::Priority.names = nil
      end
      let(:p0_payload) { default_payload.merge(priority: 'high') }
      let(:p20_payload) { default_payload.merge(priority: 'low') }

      it 'emits the expected results for each metric' do
        expect { subject.run! }
          .to emit_notification("delayed.monitor.run").with_payload(default_payload.except(:queue))
          .and emit_notification("delayed.job.count").with_payload(p0_payload).with_value(8)
          .and emit_notification("delayed.job.future_count").with_payload(p0_payload).with_value(2)
          .and emit_notification("delayed.job.locked_count").with_payload(p0_payload).with_value(4)
          .and emit_notification("delayed.job.erroring_count").with_payload(p0_payload).with_value(2)
          .and emit_notification("delayed.job.failed_count").with_payload(p0_payload).with_value(2)
          .and emit_notification("delayed.job.working_count").with_payload(p0_payload).with_value(2)
          .and emit_notification("delayed.job.workable_count").with_payload(p0_payload).with_value(2)
          .and emit_notification("delayed.job.max_age").with_payload(p0_payload).with_value(2.minutes)
          .and emit_notification("delayed.job.max_lock_age").with_payload(p0_payload).with_value(7.minutes)
          .and emit_notification("delayed.job.alert_age_percent").with_payload(p0_payload).with_value(0)
          .and emit_notification("delayed.job.count").with_payload(p20_payload).with_value(8)
          .and emit_notification("delayed.job.future_count").with_payload(p20_payload).with_value(2)
          .and emit_notification("delayed.job.locked_count").with_payload(p20_payload).with_value(4)
          .and emit_notification("delayed.job.erroring_count").with_payload(p20_payload).with_value(2)
          .and emit_notification("delayed.job.failed_count").with_payload(p20_payload).with_value(2)
          .and emit_notification("delayed.job.working_count").with_payload(p20_payload).with_value(2)
          .and emit_notification("delayed.job.workable_count").with_payload(p20_payload).with_value(2)
          .and emit_notification("delayed.job.max_age").with_payload(p20_payload).with_value(6.hours)
          .and emit_notification("delayed.job.max_lock_age").with_payload(p20_payload).with_value(11.minutes)
          .and emit_notification("delayed.job.alert_age_percent").with_payload(p20_payload).with_value(0)
          .and emit_notification("delayed.job.workable_count").with_payload(p20_payload.merge(queue: 'banana')).with_value(1)
          .and emit_notification("delayed.job.max_age").with_payload(p20_payload.merge(queue: 'banana')).with_value(4.hours)
      end

      context 'when alert thresholds are specified' do
        around do |example|
          Delayed::Priority.alerts = { high: { age: 3.hours }, low: { age: 1.year } }
          example.run
        ensure
          Delayed::Priority.alerts = nil
        end

        it 'emits the expected alert_age_percent results' do
          expect { subject.run! }
            .to emit_notification("delayed.job.alert_age_percent").with_payload(p0_payload).with_value(2.0.minutes / 3.hours * 100)
            .and emit_notification("delayed.job.alert_age_percent").with_payload(p20_payload).with_value(6.0.hours / 1.year * 100)
        end
      end
    end

    context 'when worker queues are specified' do
      around do |example|
        Delayed::Worker.queues = %w(banana gram)
        Delayed::Priority.names = { interactive: 0 } # avoid splitting by priority for simplicity
        Delayed::Priority.alerts = { interactive: { age: 8.hours } }
        example.run
      ensure
        Delayed::Priority.names = nil
        Delayed::Worker.queues = []
      end
      let(:banana_payload) { default_payload.merge(queue: 'banana', priority: 'interactive') }
      let(:gram_payload) { default_payload.merge(queue: 'gram', priority: 'interactive') }

      it 'emits the expected results for each queue' do
        expect { subject.run! }
          .to emit_notification("delayed.monitor.run").with_payload(default_payload.except(:queue))
          .and emit_notification("delayed.job.count").with_payload(banana_payload).with_value(1)
          .and emit_notification("delayed.job.future_count").with_payload(banana_payload).with_value(0)
          .and emit_notification("delayed.job.locked_count").with_payload(banana_payload).with_value(0)
          .and emit_notification("delayed.job.erroring_count").with_payload(banana_payload).with_value(0)
          .and emit_notification("delayed.job.failed_count").with_payload(banana_payload).with_value(0)
          .and emit_notification("delayed.job.working_count").with_payload(banana_payload).with_value(0)
          .and emit_notification("delayed.job.workable_count").with_payload(banana_payload).with_value(1)
          .and emit_notification("delayed.job.max_age").with_payload(banana_payload).with_value(4.hours)
          .and emit_notification("delayed.job.max_lock_age").with_payload(banana_payload).with_value(0)
          .and emit_notification("delayed.job.alert_age_percent").with_payload(banana_payload).with_value(4.0.hours / 8.hours * 100)
          .and emit_notification("delayed.job.count").with_payload(gram_payload).with_value(0)
          .and emit_notification("delayed.job.future_count").with_payload(gram_payload).with_value(0)
          .and emit_notification("delayed.job.locked_count").with_payload(gram_payload).with_value(0)
          .and emit_notification("delayed.job.erroring_count").with_payload(gram_payload).with_value(0)
          .and emit_notification("delayed.job.failed_count").with_payload(gram_payload).with_value(0)
          .and emit_notification("delayed.job.working_count").with_payload(gram_payload).with_value(0)
          .and emit_notification("delayed.job.workable_count").with_payload(gram_payload).with_value(0)
          .and emit_notification("delayed.job.max_age").with_payload(gram_payload).with_value(0)
          .and emit_notification("delayed.job.max_lock_age").with_payload(gram_payload).with_value(0)
          .and emit_notification("delayed.job.alert_age_percent").with_payload(gram_payload).with_value(0)
      end
    end
  end

  describe '#query_for' do
    let(:monitor) { described_class.new }
    let(:queries) { [] }
    let(:now) { '2025-11-10 17:20:13 UTC' }

    around { |example| Timecop.freeze(now) { example.run } }

    before do
      Delayed::Worker.queues = []
      ActiveSupport::Notifications.subscribe('sql.active_record') do |_, _, _, _, details|
        sql = details[:sql]
        details[:binds]&.each do |value|
          value = value.value if value.is_a?(ActiveModel::Attribute)
          sql = sql.sub(/(\?|\$\d)/, ActiveRecord::Base.connection.quote(value))
        end
        queries << sql
      end
    end

    def query_for(metric)
      monitor.query_for(metric)
      queries.first || raise("Expected a query for #{metric}, but none was executed")
    end

    it 'runs the expected SQL for count' do
      expect(query_for('count')).to match_sql(<<~SQL)
        SELECT COUNT(*) AS count_all,
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END AS case_when_priority_0_and_priority_10_then_0_when_priority_10_an,
          "delayed_jobs"."queue" AS delayed_jobs_queue
        FROM "delayed_jobs"
        GROUP BY
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END,
          "delayed_jobs"."queue"
      SQL
    end

    it 'runs the expected SQL for future_count' do
      expect(query_for('future_count')).to match_sql(<<~SQL)
        SELECT COUNT(*) AS count_all,
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END AS case_when_priority_0_and_priority_10_then_0_when_priority_10_an,
          "delayed_jobs"."queue" AS delayed_jobs_queue
        FROM "delayed_jobs"
        WHERE "delayed_jobs"."run_at" > '2025-11-10 17:20:13'
        GROUP BY
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END,
          "delayed_jobs"."queue"
      SQL
    end

    it 'runs the expected SQL for locked_count' do
      expect(query_for('locked_count')).to match_sql(<<~SQL)
        SELECT COUNT(*) AS count_all,
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END AS case_when_priority_0_and_priority_10_then_0_when_priority_10_an,
          "delayed_jobs"."queue" AS delayed_jobs_queue
        FROM "delayed_jobs"
        WHERE "delayed_jobs"."locked_at" IS NOT NULL
        GROUP BY
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END,
          "delayed_jobs"."queue"
      SQL
    end

    it 'runs the expected SQL for erroring_count' do
      expect(query_for('erroring_count')).to match_sql(<<~SQL)
        SELECT COUNT(*) AS count_all,
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END AS case_when_priority_0_and_priority_10_then_0_when_priority_10_an,
          "delayed_jobs"."queue" AS delayed_jobs_queue
        FROM "delayed_jobs"
        WHERE "delayed_jobs"."last_error" IS NOT NULL
        GROUP BY
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END,
          "delayed_jobs"."queue"
      SQL
    end

    it 'runs the expected SQL for failed_count' do
      expect(query_for('failed_count')).to match_sql(<<~SQL)
        SELECT COUNT(*) AS count_all,
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END AS case_when_priority_0_and_priority_10_then_0_when_priority_10_an,
          "delayed_jobs"."queue" AS delayed_jobs_queue
        FROM "delayed_jobs"
        WHERE "delayed_jobs"."failed_at" IS NOT NULL
        GROUP BY
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END,
          "delayed_jobs"."queue"
      SQL
    end

    it 'runs the expected SQL for max_lock_age' do
      expect(query_for('max_lock_age')).to match_sql(<<~SQL)
        SELECT CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END AS priority,
          queue,
          MIN(locked_at) AS locked_at
        FROM "delayed_jobs"
        WHERE "delayed_jobs"."locked_at" IS NOT NULL
          AND "delayed_jobs"."failed_at" IS NULL
        GROUP BY
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END,
          "delayed_jobs"."queue"
      SQL
    end

    it 'runs the expected SQL for max_age' do
      expect(query_for('max_age')).to match_sql(<<~SQL)
        SELECT (CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END) AS priority,
          queue,
          MIN(run_at) AS run_at
        FROM "delayed_jobs"
        WHERE "delayed_jobs"."locked_at" IS NULL
          AND "delayed_jobs"."failed_at" IS NULL
          AND "delayed_jobs"."run_at" <= '2025-11-10 17:20:13'
        GROUP BY
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END,
          "delayed_jobs"."queue"
      SQL
    end

    it 'runs the expected SQL for working_count' do
      expect(query_for('working_count')).to match_sql(<<~SQL)
        SELECT COUNT(*) AS count_all,
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END AS case_when_priority_0_and_priority_10_then_0_when_priority_10_an,
          "delayed_jobs"."queue" AS delayed_jobs_queue
        FROM "delayed_jobs"
        WHERE "delayed_jobs"."locked_at" IS NOT NULL
          AND "delayed_jobs"."failed_at" IS NULL
        GROUP BY
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END,
          "delayed_jobs"."queue"
      SQL
    end

    it 'runs the expected SQL for workable_count' do
      expect(query_for('workable_count')).to match_sql(<<~SQL)
        SELECT COUNT(*) AS count_all,
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END AS case_when_priority_0_and_priority_10_then_0_when_priority_10_an,
          "delayed_jobs"."queue" AS delayed_jobs_queue
        FROM "delayed_jobs"
        WHERE "delayed_jobs"."locked_at" IS NULL
          AND "delayed_jobs"."failed_at" IS NULL
          AND "delayed_jobs"."run_at" <= '2025-11-10 17:20:13'
        GROUP BY
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END,
          "delayed_jobs"."queue"
      SQL
    end

    it 'runs the expected SQL for alert_age_percent' do
      expect(query_for('alert_age_percent')).to match_sql(<<~SQL)
        SELECT (CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END) AS priority,
          queue,
          MIN(run_at) AS run_at
        FROM "delayed_jobs"
        WHERE "delayed_jobs"."locked_at" IS NULL
          AND "delayed_jobs"."failed_at" IS NULL
          AND "delayed_jobs"."run_at" <= '2025-11-10 17:20:13'
        GROUP BY
          CASE WHEN priority >= 0 AND priority < 10 THEN 0
            WHEN priority >= 10 AND priority < 20 THEN 10
            WHEN priority >= 20 AND priority < 30 THEN 20
            WHEN priority >= 30 THEN 30
          END,
          "delayed_jobs"."queue"
      SQL
    end
  end
end
