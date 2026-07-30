require 'helper'

RSpec.describe Delayed::Monitor do
  before do
    described_class.sleep_delay = 0
  end

  def emitted_event_names(pattern, &block)
    events = []
    callback = ->(name, *) { events << name }
    ActiveSupport::Notifications.subscribed(callback, pattern, &block)
    events
  end

  let(:default_payload) do
    {
      table: 'delayed_jobs',
      database: current_database,
      database_adapter: current_adapter,
      queue: 'default',
    }
  end

  describe '#run!' do
    let(:app_local_db_time) { false }

    around do |example|
      if app_local_db_time
        Time.zone = 'US/Central'
        self.default_timezone = :local
      end

      # On PostgreSQL, running examples in a transaction allows CURRENT_TIMESTAMP to remain stable.
      # We can in turn use this to set Timecop to the same time as the DB for deterministic time math.
      Delayed::Job.transaction do
        now = described_class.parse_utc_time(
          Delayed::Job.connection.select_value("SELECT #{described_class.sql_now_in_utc}"),
        )
        Timecop.freeze(now) { example.run }
      end
    ensure
      Time.zone = nil
      self.default_timezone = :utc
    end

    let(:now) { Delayed::Job.db_time_now }

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
        .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'interactive')).approximately.with_value(0)
        .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'user_visible')).approximately.with_value(0)
        .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'eventual')).approximately.with_value(0)
        .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'reporting')).approximately.with_value(0)
        .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'interactive')).approximately.with_value(0)
        .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'user_visible')).approximately.with_value(0)
        .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'eventual')).approximately.with_value(0)
        .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'reporting')).approximately.with_value(0)
        .and emit_notification("delayed.job.alert_age_percent").with_payload(default_payload.merge(priority: 'interactive')).approximately.with_value(0)
        .and emit_notification("delayed.job.alert_age_percent").with_payload(default_payload.merge(priority: 'user_visible')).approximately.with_value(0)
        .and emit_notification("delayed.job.alert_age_percent").with_payload(default_payload.merge(priority: 'eventual')).approximately.with_value(0)
        .and emit_notification("delayed.job.alert_age_percent").with_payload(default_payload.merge(priority: 'reporting')).approximately.with_value(0)
    end

    it 'does not emit max_age_by_name when no jobs are present' do
      expect(emitted_event_names("delayed.job.max_age_by_name") { subject.run! }).to be_empty
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
          .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'high')).approximately.with_value(0)
          .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'low')).approximately.with_value(0)
          .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'high')).approximately.with_value(0)
          .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'low')).approximately.with_value(0)
          .and emit_notification("delayed.job.alert_age_percent").with_payload(default_payload.merge(priority: 'high')).with_value(0)
          .and emit_notification("delayed.job.alert_age_percent").with_payload(default_payload.merge(priority: 'low')).with_value(0)
      end
    end

    context 'when there are jobs in the queue' do
      let(:job_attributes) do
        {
          run_at: now,
          queue: 'default',
          handler: "--- !ruby/object:SimpleJob\n",
          name: 'SimpleJob',
          attempts: 0,
        }
      end
      let(:failed_attributes) { { run_at: now - 1.week, attempts: 1, failed_at: now - 1.day, locked_at: now - 1.day } }
      let(:p0_attributes) { job_attributes.merge(priority: 1, attempts: 1) }
      let(:p10_attributes) { job_attributes.merge(priority: 13, locked_at: now - 1.day) }
      let(:p20_attributes) { job_attributes.merge(priority: 23, attempts: 1) }
      let(:p30_attributes) { job_attributes.merge(priority: 999, locked_at: now - 1.day) }
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

      it 'emits the expected results for each metric' do
        expect { subject.run! }
          .to emit_notification("delayed.monitor.run").with_payload(default_payload.except(:queue))
          .and emit_notification("delayed.job.count").with_payload(p0_payload).with_value(4)
          .and emit_notification("delayed.job.future_count").with_payload(p0_payload).with_value(1)
          .and emit_notification("delayed.job.locked_count").with_payload(p0_payload).with_value(1)
          .and emit_notification("delayed.job.erroring_count").with_payload(p0_payload).with_value(3)
          .and emit_notification("delayed.job.failed_count").with_payload(p0_payload).with_value(1)
          .and emit_notification("delayed.job.working_count").with_payload(p0_payload).with_value(1)
          .and emit_notification("delayed.job.workable_count").with_payload(p0_payload).with_value(1)
          .and emit_notification("delayed.job.max_age").with_payload(p0_payload).approximately.with_value(30.seconds)
          .and emit_notification("delayed.job.max_lock_age").with_payload(p0_payload).approximately.with_value(3.minutes)
          .and emit_notification("delayed.job.alert_age_percent").with_payload(p0_payload).approximately.with_value(30.0.seconds / 1.minute * 100)
          .and emit_notification("delayed.job.count").with_payload(p10_payload).with_value(4)
          .and emit_notification("delayed.job.future_count").with_payload(p10_payload).with_value(1)
          .and emit_notification("delayed.job.locked_count").with_payload(p10_payload).with_value(1)
          .and emit_notification("delayed.job.erroring_count").with_payload(p10_payload).with_value(0)
          .and emit_notification("delayed.job.failed_count").with_payload(p10_payload).with_value(1)
          .and emit_notification("delayed.job.working_count").with_payload(p10_payload).with_value(1)
          .and emit_notification("delayed.job.workable_count").with_payload(p10_payload).with_value(1)
          .and emit_notification("delayed.job.max_age").with_payload(p10_payload).approximately.with_value(2.minutes)
          .and emit_notification("delayed.job.max_lock_age").with_payload(p10_payload).approximately.with_value(7.minutes)
          .and emit_notification("delayed.job.alert_age_percent").with_payload(p10_payload).approximately.with_value(2.0.minutes / 3.minutes * 100)
          .and emit_notification("delayed.job.count").with_payload(p20_payload).with_value(4)
          .and emit_notification("delayed.job.future_count").with_payload(p20_payload).with_value(1)
          .and emit_notification("delayed.job.locked_count").with_payload(p20_payload).with_value(1)
          .and emit_notification("delayed.job.erroring_count").with_payload(p20_payload).with_value(3)
          .and emit_notification("delayed.job.failed_count").with_payload(p20_payload).with_value(1)
          .and emit_notification("delayed.job.working_count").with_payload(p20_payload).with_value(1)
          .and emit_notification("delayed.job.workable_count").with_payload(p20_payload).with_value(1)
          .and emit_notification("delayed.job.max_age").with_payload(p20_payload).approximately.with_value(1.hour)
          .and emit_notification("delayed.job.max_lock_age").with_payload(p20_payload).approximately.with_value(9.minutes)
          .and emit_notification("delayed.job.alert_age_percent").with_payload(p20_payload).approximately.with_value(1.hour / 1.5.hours * 100)
          .and emit_notification("delayed.job.count").with_payload(p30_payload).with_value(4)
          .and emit_notification("delayed.job.future_count").with_payload(p30_payload).with_value(1)
          .and emit_notification("delayed.job.locked_count").with_payload(p30_payload).with_value(1)
          .and emit_notification("delayed.job.erroring_count").with_payload(p30_payload).with_value(0)
          .and emit_notification("delayed.job.failed_count").with_payload(p30_payload).with_value(1)
          .and emit_notification("delayed.job.working_count").with_payload(p30_payload).with_value(1)
          .and emit_notification("delayed.job.workable_count").with_payload(p30_payload).with_value(1)
          .and emit_notification("delayed.job.max_age").with_payload(p30_payload).approximately.with_value(6.hours)
          .and emit_notification("delayed.job.max_lock_age").with_payload(p30_payload).approximately.with_value(11.minutes)
          .and emit_notification("delayed.job.alert_age_percent").with_payload(p30_payload).approximately.with_value(100) # 6 hours / 4 hours (overflow)
          .and emit_notification("delayed.job.workable_count").with_payload(p30_payload.merge(queue: 'banana')).with_value(1)
          .and emit_notification("delayed.job.max_age").with_payload(p30_payload.merge(queue: 'banana')).approximately.with_value(4.hours)
      end

      it 'emits max_age_by_name grouped by job name' do
        expect { subject.run! }
          .to emit_notification("delayed.job.max_age_by_name").with_payload(p0_payload.merge(name: 'SimpleJob')).approximately.with_value(30.seconds)
          .and emit_notification("delayed.job.max_age_by_name").with_payload(p10_payload.merge(name: 'SimpleJob')).approximately.with_value(2.minutes)
          .and emit_notification("delayed.job.max_age_by_name").with_payload(p20_payload.merge(name: 'SimpleJob')).approximately.with_value(1.hour)
          .and emit_notification("delayed.job.max_age_by_name").with_payload(p30_payload.merge(name: 'SimpleJob')).approximately.with_value(6.hours)
          .and emit_notification("delayed.job.max_age_by_name").with_payload(p30_payload.merge(queue: 'banana', name: 'SimpleJob')).approximately.with_value(4.hours)
      end

      context 'when multiple job names share a priority and queue' do
        let!(:other_named_job) { Delayed::Job.create! p0_attributes.merge(name: 'OtherJob', run_at: now - 10.minutes) }

        it 'emits a separate max_age_by_name series per name' do
          expect { subject.run! }
            .to emit_notification("delayed.job.max_age_by_name").with_payload(p0_payload.merge(name: 'SimpleJob')).approximately.with_value(30.seconds)
            .and emit_notification("delayed.job.max_age_by_name").with_payload(p0_payload.merge(name: 'OtherJob')).approximately.with_value(10.minutes)
        end
      end

      context 'when metrics_by_attribute is empty' do
        around do |example|
          described_class.metrics_by_attribute = {}
          example.run
        ensure
          described_class.metrics_by_attribute = { max_age: %i(name) }
        end

        it 'does not emit max_age_by_name' do
          expect(emitted_event_names("delayed.job.max_age_by_name") { subject.run! }).to be_empty
        end
      end

      context 'when the delayed_jobs table has no name column' do
        before do
          allow(Delayed::Job).to receive(:column_names).and_return(Delayed::Job.column_names - ['name'])
        end

        it 'does not emit max_age_by_name' do
          expect(emitted_event_names("delayed.job.max_age_by_name") { subject.run! }).to be_empty
        end
      end

      context 'when a job predates the name column' do
        around do |example|
          ValidateRunAtAndNameNotNull.migrate(:down)
          AddRunAtAndNameNotNullCheck.migrate(:down)
          example.run
        ensure
          Delayed::Job.delete_all
          AddRunAtAndNameNotNullCheck.migrate(:up)
          ValidateRunAtAndNameNotNull.migrate(:up)
        end

        let!(:unnamed_job) { Delayed::Job.create! p0_attributes.merge(name: nil, run_at: now - 10.minutes) }

        it "emits max_age_by_name under the name 'unknown'" do
          expect { subject.run! }
            .to emit_notification("delayed.job.max_age_by_name").with_payload(p0_payload.merge(name: 'unknown')).approximately.with_value(10.minutes)
        end
      end

      context 'when metrics_by_attribute pairs metrics with a custom column' do
        around do |example|
          Delayed::Job.connection.add_column :delayed_jobs, :owner, :string
          Delayed::Job.reset_column_information
          described_class.metrics_by_attribute = { max_age: %i(name owner), failed_count: %i(owner) }
          example.run
        ensure
          described_class.metrics_by_attribute = { max_age: %i(name) }
          Delayed::Job.connection.remove_column :delayed_jobs, :owner
          Delayed::Job.reset_column_information
        end

        let!(:team_a_job) { Delayed::Job.create! p0_attributes.merge(owner: 'team_a', run_at: now - 10.minutes) }
        let!(:team_b_job) { Delayed::Job.create! p0_attributes.merge(owner: 'team_b', run_at: now - 20.minutes) }

        it "emits a max_age_by_owner series per owner, reporting ownerless rows as 'unknown'" do
          expect { subject.run! }
            .to emit_notification("delayed.job.max_age_by_owner").with_payload(p0_payload.merge(owner: 'team_a')).approximately.with_value(10.minutes)
            .and emit_notification("delayed.job.max_age_by_owner").with_payload(p0_payload.merge(owner: 'team_b')).approximately.with_value(20.minutes)
            .and emit_notification("delayed.job.max_age_by_owner").with_payload(p0_payload.merge(owner: 'unknown')).approximately.with_value(30.seconds)
        end

        it 'emits other paired metrics by the same column' do
          expect { subject.run! }
            .to emit_notification("delayed.job.failed_count_by_owner").with_payload(p0_payload.merge(owner: 'unknown')).with_value(1)
        end

        it 'emits max_age_by_name independently, without owner tags' do
          expect { subject.run! }
            .to emit_notification("delayed.job.max_age_by_name").with_payload(p0_payload.merge(name: 'SimpleJob')).approximately.with_value(20.minutes)
        end
      end

      context 'when metrics_by_attribute names a column that does not exist' do
        around do |example|
          described_class.metrics_by_attribute = { max_age: %i(name owner) }
          example.run
        ensure
          described_class.metrics_by_attribute = { max_age: %i(name) }
        end

        it 'skips the missing column but still emits max_age_by_name' do
          events = emitted_event_names(/delayed\.job\.max_age_by_/) { subject.run! }
          expect(events).to include("delayed.job.max_age_by_name")
          expect(events).not_to include("delayed.job.max_age_by_owner")
        end
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
            .and emit_notification("delayed.job.locked_count").with_payload(p0_payload).with_value(2)
            .and emit_notification("delayed.job.erroring_count").with_payload(p0_payload).with_value(3)
            .and emit_notification("delayed.job.failed_count").with_payload(p0_payload).with_value(2)
            .and emit_notification("delayed.job.working_count").with_payload(p0_payload).with_value(2)
            .and emit_notification("delayed.job.workable_count").with_payload(p0_payload).with_value(2)
            .and emit_notification("delayed.job.max_age").with_payload(p0_payload).approximately.with_value(2.minutes)
            .and emit_notification("delayed.job.max_lock_age").with_payload(p0_payload).approximately.with_value(7.minutes)
            .and emit_notification("delayed.job.alert_age_percent").with_payload(p0_payload).approximately.with_value(0)
            .and emit_notification("delayed.job.count").with_payload(p20_payload).with_value(8)
            .and emit_notification("delayed.job.future_count").with_payload(p20_payload).with_value(2)
            .and emit_notification("delayed.job.locked_count").with_payload(p20_payload).with_value(2)
            .and emit_notification("delayed.job.erroring_count").with_payload(p20_payload).with_value(3)
            .and emit_notification("delayed.job.failed_count").with_payload(p20_payload).with_value(2)
            .and emit_notification("delayed.job.working_count").with_payload(p20_payload).with_value(2)
            .and emit_notification("delayed.job.workable_count").with_payload(p20_payload).with_value(2)
            .and emit_notification("delayed.job.max_age").with_payload(p20_payload).approximately.with_value(6.hours)
            .and emit_notification("delayed.job.max_lock_age").with_payload(p20_payload).approximately.with_value(11.minutes)
            .and emit_notification("delayed.job.alert_age_percent").with_payload(p20_payload).approximately.with_value(0)
            .and emit_notification("delayed.job.workable_count").with_payload(p20_payload.merge(queue: 'banana')).with_value(1)
            .and emit_notification("delayed.job.max_age").with_payload(p20_payload.merge(queue: 'banana')).approximately.with_value(4.hours)
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
              .to emit_notification("delayed.job.alert_age_percent").with_payload(p0_payload).approximately.with_value(2.0.minutes / 3.hours * 100)
              .and emit_notification("delayed.job.alert_age_percent").with_payload(p20_payload).approximately.with_value(6.0.hours / 1.year * 100)
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
            .and emit_notification("delayed.job.max_age").with_payload(banana_payload).approximately.with_value(4.hours)
            .and emit_notification("delayed.job.max_lock_age").with_payload(banana_payload).approximately.with_value(0)
            .and emit_notification("delayed.job.alert_age_percent").with_payload(banana_payload).approximately.with_value(4.0.hours / 8.hours * 100)
            .and emit_notification("delayed.job.count").with_payload(gram_payload).with_value(0)
            .and emit_notification("delayed.job.future_count").with_payload(gram_payload).with_value(0)
            .and emit_notification("delayed.job.locked_count").with_payload(gram_payload).with_value(0)
            .and emit_notification("delayed.job.erroring_count").with_payload(gram_payload).with_value(0)
            .and emit_notification("delayed.job.failed_count").with_payload(gram_payload).with_value(0)
            .and emit_notification("delayed.job.working_count").with_payload(gram_payload).with_value(0)
            .and emit_notification("delayed.job.workable_count").with_payload(gram_payload).with_value(0)
            .and emit_notification("delayed.job.max_age").with_payload(gram_payload).approximately.with_value(0)
            .and emit_notification("delayed.job.max_lock_age").with_payload(gram_payload).approximately.with_value(0)
            .and emit_notification("delayed.job.alert_age_percent").with_payload(gram_payload).approximately.with_value(0)
        end
      end

      context 'when using app-local timezone for DB timestamps' do
        let(:app_local_db_time) { true }

        it 'emits the expected results for each metric' do
          expect { subject.run! }
            .to emit_notification("delayed.monitor.run").with_payload(default_payload.except(:queue))
            .and emit_notification("delayed.job.count").with_payload(p0_payload).with_value(4)
            .and emit_notification("delayed.job.future_count").with_payload(p0_payload).with_value(1)
            .and emit_notification("delayed.job.locked_count").with_payload(p0_payload).with_value(1)
            .and emit_notification("delayed.job.erroring_count").with_payload(p0_payload).with_value(3)
            .and emit_notification("delayed.job.failed_count").with_payload(p0_payload).with_value(1)
            .and emit_notification("delayed.job.working_count").with_payload(p0_payload).with_value(1)
            .and emit_notification("delayed.job.workable_count").with_payload(p0_payload).with_value(1)
            .and emit_notification("delayed.job.max_age").with_payload(p0_payload).approximately.with_value(30.seconds)
            .and emit_notification("delayed.job.max_lock_age").with_payload(p0_payload).approximately.with_value(3.minutes)
            .and emit_notification("delayed.job.alert_age_percent").with_payload(p0_payload).approximately.with_value(30.0.seconds / 1.minute * 100)
            .and emit_notification("delayed.job.count").with_payload(p10_payload).with_value(4)
            .and emit_notification("delayed.job.future_count").with_payload(p10_payload).with_value(1)
            .and emit_notification("delayed.job.locked_count").with_payload(p10_payload).with_value(1)
            .and emit_notification("delayed.job.erroring_count").with_payload(p10_payload).with_value(0)
            .and emit_notification("delayed.job.failed_count").with_payload(p10_payload).with_value(1)
            .and emit_notification("delayed.job.working_count").with_payload(p10_payload).with_value(1)
            .and emit_notification("delayed.job.workable_count").with_payload(p10_payload).with_value(1)
            .and emit_notification("delayed.job.max_age").with_payload(p10_payload).approximately.with_value(2.minutes)
            .and emit_notification("delayed.job.max_lock_age").with_payload(p10_payload).approximately.with_value(7.minutes)
            .and emit_notification("delayed.job.alert_age_percent").with_payload(p10_payload).approximately.with_value(2.0.minutes / 3.minutes * 100)
            .and emit_notification("delayed.job.count").with_payload(p20_payload).with_value(4)
            .and emit_notification("delayed.job.future_count").with_payload(p20_payload).with_value(1)
            .and emit_notification("delayed.job.locked_count").with_payload(p20_payload).with_value(1)
            .and emit_notification("delayed.job.erroring_count").with_payload(p20_payload).with_value(3)
            .and emit_notification("delayed.job.failed_count").with_payload(p20_payload).with_value(1)
            .and emit_notification("delayed.job.working_count").with_payload(p20_payload).with_value(1)
            .and emit_notification("delayed.job.workable_count").with_payload(p20_payload).with_value(1)
            .and emit_notification("delayed.job.max_age").with_payload(p20_payload).approximately.with_value(1.hour)
            .and emit_notification("delayed.job.max_lock_age").with_payload(p20_payload).approximately.with_value(9.minutes)
            .and emit_notification("delayed.job.alert_age_percent").with_payload(p20_payload).approximately.with_value(1.hour / 1.5.hours * 100)
            .and emit_notification("delayed.job.count").with_payload(p30_payload).with_value(4)
            .and emit_notification("delayed.job.future_count").with_payload(p30_payload).with_value(1)
            .and emit_notification("delayed.job.locked_count").with_payload(p30_payload).with_value(1)
            .and emit_notification("delayed.job.erroring_count").with_payload(p30_payload).with_value(0)
            .and emit_notification("delayed.job.failed_count").with_payload(p30_payload).with_value(1)
            .and emit_notification("delayed.job.working_count").with_payload(p30_payload).with_value(1)
            .and emit_notification("delayed.job.workable_count").with_payload(p30_payload).with_value(1)
            .and emit_notification("delayed.job.max_age").with_payload(p30_payload).approximately.with_value(6.hours)
            .and emit_notification("delayed.job.max_lock_age").with_payload(p30_payload).approximately.with_value(11.minutes)
            .and emit_notification("delayed.job.alert_age_percent").with_payload(p30_payload).approximately.with_value(100) # 6 hours / 4 hours (overflow)
            .and emit_notification("delayed.job.workable_count").with_payload(p30_payload.merge(queue: 'banana')).with_value(1)
            .and emit_notification("delayed.job.max_age").with_payload(p30_payload.merge(queue: 'banana')).approximately.with_value(4.hours)
        end
      end
    end

    context 'when a job is locked (in-flight)' do
      let(:payload) { default_payload.merge(priority: 'interactive') }
      let(:base_attributes) do
        {
          priority: 0,
          queue: 'default',
          handler: "--- !ruby/object:SimpleJob\n",
          name: 'SimpleJob',
          attempts: 0,
        }
      end

      # A single slow, in-flight job: old run_at, but currently locked by a worker.
      let!(:locked_job) { Delayed::Job.create! base_attributes.merge(run_at: now - 1.hour, locked_at: now - 5.minutes) }

      it 'excludes the locked job from max_age and alert_age_percent' do
        expect { subject.run! }
          .to emit_notification("delayed.job.locked_count").with_payload(payload).with_value(1)
          .and emit_notification("delayed.job.workable_count").with_payload(payload).with_value(0)
          .and emit_notification("delayed.job.max_lock_age").with_payload(payload).approximately.with_value(5.minutes)
          .and emit_notification("delayed.job.max_age").with_payload(payload).approximately.with_value(0)
          .and emit_notification("delayed.job.alert_age_percent").with_payload(payload).approximately.with_value(0)
      end

      it 'excludes the locked job from max_age_by_name' do
        expect { subject.run! }
          .to emit_notification("delayed.job.max_age_by_name").with_payload(payload.merge(name: 'SimpleJob')).approximately.with_value(0)
      end

      context 'and a workable job is also present in the same group' do
        # The workable job's run_at is newer than the locked job's, so max_age must
        # track the workable job (30s), not the locked job (1 hour).
        let!(:workable_job) { Delayed::Job.create! base_attributes.merge(run_at: now - 30.seconds) }

        it 'reports max_age from the workable job only' do
          expect { subject.run! }
            .to emit_notification("delayed.job.locked_count").with_payload(payload).with_value(1)
            .and emit_notification("delayed.job.workable_count").with_payload(payload).with_value(1)
            .and emit_notification("delayed.job.max_age").with_payload(payload).approximately.with_value(30.seconds)
        end
      end
    end
  end

  describe '.metrics_by_attribute=' do
    it 'rejects unknown metrics at assignment time' do
      expect { described_class.metrics_by_attribute = { min_age: %i(name) } }
        .to raise_error(ArgumentError, /Unknown metrics in metrics_by_attribute: min_age/)
    end
  end

  describe 'SQL' do
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
        queries << QueryUnderTest.for(sql)
        queries << "---"
      end
    end

    def query_descriptions
      (described_class::METRICS + %w(max_age_by_name)).each do |metric|
        queries << "-- QUERIES FOR `#{metric}`:"
        queries << "---------------------------------"
        base, attribute = metric.split('_by_')
        monitor.query_for(base, *[attribute&.to_sym].compact)
        queries << "-- (no new queries)" unless queries.last == '---'
      end
      queries.dup.map { |query| query.try(:full_description) || query }
    end

    it "runs the expected #{current_adapter} queries with the expected plans" do
      expect(query_descriptions.join("\n")).to match_snapshot
    end

    context 'when using the legacy index', :with_legacy_table_index do
      it "[legacy index] runs the expected #{current_adapter} queries with the expected plans" do
        expect(query_descriptions.join("\n")).to match_snapshot
      end
    end
  end
end
