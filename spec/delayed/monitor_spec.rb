require 'helper'

RSpec.describe Delayed::Monitor do
  let(:default_payload) do
    {
      table: 'delayed_jobs',
      database: current_database,
      database_adapter: current_adapter,
      queue: 'default_tracking',
    }
  end

  it 'emits empty metrics for all default priorities' do
    expect { subject.run! }
      .to emit_notification("delayed.monitor.run").with_payload(default_payload.except(:queue))
      .and emit_notification("delayed.job.count").with_payload(default_payload.merge(priority: 'interactive', value: 0))
      .and emit_notification("delayed.job.count").with_payload(default_payload.merge(priority: 'user_visible', value: 0))
      .and emit_notification("delayed.job.count").with_payload(default_payload.merge(priority: 'eventual', value: 0))
      .and emit_notification("delayed.job.count").with_payload(default_payload.merge(priority: 'reporting', value: 0))
      .and emit_notification("delayed.job.future_count").with_payload(default_payload.merge(priority: 'interactive', value: 0))
      .and emit_notification("delayed.job.future_count").with_payload(default_payload.merge(priority: 'user_visible', value: 0))
      .and emit_notification("delayed.job.future_count").with_payload(default_payload.merge(priority: 'eventual', value: 0))
      .and emit_notification("delayed.job.future_count").with_payload(default_payload.merge(priority: 'reporting', value: 0))
      .and emit_notification("delayed.job.locked_count").with_payload(default_payload.merge(priority: 'interactive', value: 0))
      .and emit_notification("delayed.job.locked_count").with_payload(default_payload.merge(priority: 'user_visible', value: 0))
      .and emit_notification("delayed.job.locked_count").with_payload(default_payload.merge(priority: 'eventual', value: 0))
      .and emit_notification("delayed.job.locked_count").with_payload(default_payload.merge(priority: 'reporting', value: 0))
      .and emit_notification("delayed.job.erroring_count").with_payload(default_payload.merge(priority: 'interactive', value: 0))
      .and emit_notification("delayed.job.erroring_count").with_payload(default_payload.merge(priority: 'user_visible', value: 0))
      .and emit_notification("delayed.job.erroring_count").with_payload(default_payload.merge(priority: 'eventual', value: 0))
      .and emit_notification("delayed.job.erroring_count").with_payload(default_payload.merge(priority: 'reporting', value: 0))
      .and emit_notification("delayed.job.failed_count").with_payload(default_payload.merge(priority: 'interactive', value: 0))
      .and emit_notification("delayed.job.failed_count").with_payload(default_payload.merge(priority: 'user_visible', value: 0))
      .and emit_notification("delayed.job.failed_count").with_payload(default_payload.merge(priority: 'eventual', value: 0))
      .and emit_notification("delayed.job.failed_count").with_payload(default_payload.merge(priority: 'reporting', value: 0))
      .and emit_notification("delayed.job.working_count").with_payload(default_payload.merge(priority: 'interactive', value: 0))
      .and emit_notification("delayed.job.working_count").with_payload(default_payload.merge(priority: 'user_visible', value: 0))
      .and emit_notification("delayed.job.working_count").with_payload(default_payload.merge(priority: 'eventual', value: 0))
      .and emit_notification("delayed.job.working_count").with_payload(default_payload.merge(priority: 'reporting', value: 0))
      .and emit_notification("delayed.job.workable_count").with_payload(default_payload.merge(priority: 'interactive', value: 0))
      .and emit_notification("delayed.job.workable_count").with_payload(default_payload.merge(priority: 'user_visible', value: 0))
      .and emit_notification("delayed.job.workable_count").with_payload(default_payload.merge(priority: 'eventual', value: 0))
      .and emit_notification("delayed.job.workable_count").with_payload(default_payload.merge(priority: 'reporting', value: 0))
      .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'interactive', value: 0))
      .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'user_visible', value: 0))
      .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'eventual', value: 0))
      .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'reporting', value: 0))
      .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'interactive', value: 0))
      .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'user_visible', value: 0))
      .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'eventual', value: 0))
      .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'reporting', value: 0))
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
        .and emit_notification("delayed.job.count").with_payload(default_payload.merge(priority: 'high', value: 0))
        .and emit_notification("delayed.job.count").with_payload(default_payload.merge(priority: 'low', value: 0))
        .and emit_notification("delayed.job.future_count").with_payload(default_payload.merge(priority: 'high', value: 0))
        .and emit_notification("delayed.job.future_count").with_payload(default_payload.merge(priority: 'low', value: 0))
        .and emit_notification("delayed.job.locked_count").with_payload(default_payload.merge(priority: 'high', value: 0))
        .and emit_notification("delayed.job.locked_count").with_payload(default_payload.merge(priority: 'low', value: 0))
        .and emit_notification("delayed.job.erroring_count").with_payload(default_payload.merge(priority: 'high', value: 0))
        .and emit_notification("delayed.job.erroring_count").with_payload(default_payload.merge(priority: 'low', value: 0))
        .and emit_notification("delayed.job.failed_count").with_payload(default_payload.merge(priority: 'high', value: 0))
        .and emit_notification("delayed.job.failed_count").with_payload(default_payload.merge(priority: 'low', value: 0))
        .and emit_notification("delayed.job.working_count").with_payload(default_payload.merge(priority: 'high', value: 0))
        .and emit_notification("delayed.job.working_count").with_payload(default_payload.merge(priority: 'low', value: 0))
        .and emit_notification("delayed.job.workable_count").with_payload(default_payload.merge(priority: 'high', value: 0))
        .and emit_notification("delayed.job.workable_count").with_payload(default_payload.merge(priority: 'low', value: 0))
        .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'high', value: 0))
        .and emit_notification("delayed.job.max_age").with_payload(default_payload.merge(priority: 'low', value: 0))
        .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'high', value: 0))
        .and emit_notification("delayed.job.max_lock_age").with_payload(default_payload.merge(priority: 'low', value: 0))
    end
  end

  context 'when there are jobs in the queue' do
    let(:now) { Time.now.change(nsec: 0) } # rubocop:disable Rails/TimeZone
    let(:job_attributes) do
      {
        run_at: now,
        queue: 'default_tracking',
        handler: "--- !ruby/object:SimpleJob\n",
        attempts: 0,
      }
    end
    let(:p0_attributes) { job_attributes.merge(priority: 1) }
    let(:p10_attributes) { job_attributes.merge(priority: 13) }
    let(:p20_attributes) { job_attributes.merge(priority: 23) }
    let(:p30_attributes) { job_attributes.merge(priority: 999) }
    let(:p0_payload) { default_payload.merge(priority: 'interactive') }
    let(:p10_payload) { default_payload.merge(priority: 'user_visible') }
    let(:p20_payload) { default_payload.merge(priority: 'eventual') }
    let(:p30_payload) { default_payload.merge(priority: 'reporting') }
    let!(:p0_workable_job) { Delayed::Job.create! p0_attributes.merge(run_at: now - 1.hour) }
    let!(:p0_failed_job) { Delayed::Job.create! p0_attributes.merge(run_at: now, last_error: '123', failed_at: now, attempts: 4) }
    let!(:p0_future_job) { Delayed::Job.create! p0_attributes.merge(run_at: now + 1.hour) }
    let!(:p0_working_job) { Delayed::Job.create! p0_attributes.merge(locked_at: now - 3.minutes) }
    let!(:p10_workable_job) { Delayed::Job.create! p10_attributes.merge(run_at: now - 2.hours) }
    let!(:p10_failed_job) { Delayed::Job.create! p10_attributes.merge(run_at: now, last_error: '123', failed_at: now, attempts: 4) }
    let!(:p10_future_job) { Delayed::Job.create! p10_attributes.merge(run_at: now + 1.hour) }
    let!(:p10_working_job) { Delayed::Job.create! p10_attributes.merge(locked_at: now - 7.minutes) }
    let!(:p20_workable_job) { Delayed::Job.create! p20_attributes.merge(run_at: now - 3.hours) }
    let!(:p20_failed_job) { Delayed::Job.create! p20_attributes.merge(run_at: now, last_error: '123', failed_at: now, attempts: 4) }
    let!(:p20_future_job) { Delayed::Job.create! p20_attributes.merge(run_at: now + 1.hour) }
    let!(:p20_working_job) { Delayed::Job.create! p20_attributes.merge(locked_at: now - 9.minutes) }
    let!(:p30_workable_job) { Delayed::Job.create! p30_attributes.merge(run_at: now - 4.hours) }
    let!(:p30_failed_job) { Delayed::Job.create! p30_attributes.merge(run_at: now, last_error: '123', failed_at: now, attempts: 4) }
    let!(:p30_future_job) { Delayed::Job.create! p30_attributes.merge(run_at: now + 1.hour) }
    let!(:p30_working_job) { Delayed::Job.create! p30_attributes.merge(locked_at: now - 11.minutes) }
    let!(:p30_workable_job_in_other_queue) { Delayed::Job.create! p30_attributes.merge(run_at: now - 4.hours, queue: 'banana') }

    around do |example|
      Timecop.freeze(now) { example.run }
    end

    it 'emits the expected results for each metric' do
      expect { subject.run! }
        .to emit_notification("delayed.monitor.run").with_payload(default_payload.except(:queue))
        .and emit_notification("delayed.job.count").with_payload(p0_payload.merge(value: 4))
        .and emit_notification("delayed.job.future_count").with_payload(p0_payload.merge(value: 1))
        .and emit_notification("delayed.job.locked_count").with_payload(p0_payload.merge(value: 1))
        .and emit_notification("delayed.job.erroring_count").with_payload(p0_payload.merge(value: 1))
        .and emit_notification("delayed.job.failed_count").with_payload(p0_payload.merge(value: 1))
        .and emit_notification("delayed.job.working_count").with_payload(p0_payload.merge(value: 1))
        .and emit_notification("delayed.job.workable_count").with_payload(p0_payload.merge(value: 1))
        .and emit_notification("delayed.job.max_age").with_payload(p0_payload.merge(value: 1.hour))
        .and emit_notification("delayed.job.max_lock_age").with_payload(p0_payload.merge(value: 3.minutes))
        .and emit_notification("delayed.job.count").with_payload(p10_payload.merge(value: 4))
        .and emit_notification("delayed.job.future_count").with_payload(p10_payload.merge(value: 1))
        .and emit_notification("delayed.job.locked_count").with_payload(p10_payload.merge(value: 1))
        .and emit_notification("delayed.job.erroring_count").with_payload(p10_payload.merge(value: 1))
        .and emit_notification("delayed.job.failed_count").with_payload(p10_payload.merge(value: 1))
        .and emit_notification("delayed.job.working_count").with_payload(p10_payload.merge(value: 1))
        .and emit_notification("delayed.job.workable_count").with_payload(p10_payload.merge(value: 1))
        .and emit_notification("delayed.job.max_age").with_payload(p10_payload.merge(value: 2.hours))
        .and emit_notification("delayed.job.max_lock_age").with_payload(p10_payload.merge(value: 7.minutes))
        .and emit_notification("delayed.job.count").with_payload(p20_payload.merge(value: 4))
        .and emit_notification("delayed.job.future_count").with_payload(p20_payload.merge(value: 1))
        .and emit_notification("delayed.job.locked_count").with_payload(p20_payload.merge(value: 1))
        .and emit_notification("delayed.job.erroring_count").with_payload(p20_payload.merge(value: 1))
        .and emit_notification("delayed.job.failed_count").with_payload(p20_payload.merge(value: 1))
        .and emit_notification("delayed.job.working_count").with_payload(p20_payload.merge(value: 1))
        .and emit_notification("delayed.job.workable_count").with_payload(p20_payload.merge(value: 1))
        .and emit_notification("delayed.job.max_age").with_payload(p20_payload.merge(value: 3.hours))
        .and emit_notification("delayed.job.max_lock_age").with_payload(p20_payload.merge(value: 9.minutes))
        .and emit_notification("delayed.job.count").with_payload(p30_payload.merge(value: 4))
        .and emit_notification("delayed.job.future_count").with_payload(p30_payload.merge(value: 1))
        .and emit_notification("delayed.job.locked_count").with_payload(p30_payload.merge(value: 1))
        .and emit_notification("delayed.job.erroring_count").with_payload(p30_payload.merge(value: 1))
        .and emit_notification("delayed.job.failed_count").with_payload(p30_payload.merge(value: 1))
        .and emit_notification("delayed.job.working_count").with_payload(p30_payload.merge(value: 1))
        .and emit_notification("delayed.job.workable_count").with_payload(p30_payload.merge(value: 1))
        .and emit_notification("delayed.job.max_age").with_payload(p30_payload.merge(value: 4.hours))
        .and emit_notification("delayed.job.max_lock_age").with_payload(p30_payload.merge(value: 11.minutes))
        .and emit_notification("delayed.job.workable_count").with_payload(p30_payload.merge(value: 1, queue: 'banana'))
        .and emit_notification("delayed.job.max_age").with_payload(p30_payload.merge(value: 4.hours, queue: 'banana'))
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
          .and emit_notification("delayed.job.count").with_payload(p0_payload.merge(value: 8))
          .and emit_notification("delayed.job.future_count").with_payload(p0_payload.merge(value: 2))
          .and emit_notification("delayed.job.locked_count").with_payload(p0_payload.merge(value: 2))
          .and emit_notification("delayed.job.erroring_count").with_payload(p0_payload.merge(value: 2))
          .and emit_notification("delayed.job.failed_count").with_payload(p0_payload.merge(value: 2))
          .and emit_notification("delayed.job.working_count").with_payload(p0_payload.merge(value: 2))
          .and emit_notification("delayed.job.workable_count").with_payload(p0_payload.merge(value: 2))
          .and emit_notification("delayed.job.max_age").with_payload(p0_payload.merge(value: 2.hours))
          .and emit_notification("delayed.job.max_lock_age").with_payload(p0_payload.merge(value: 7.minutes))
          .and emit_notification("delayed.job.count").with_payload(p20_payload.merge(value: 8))
          .and emit_notification("delayed.job.future_count").with_payload(p20_payload.merge(value: 2))
          .and emit_notification("delayed.job.locked_count").with_payload(p20_payload.merge(value: 2))
          .and emit_notification("delayed.job.erroring_count").with_payload(p20_payload.merge(value: 2))
          .and emit_notification("delayed.job.failed_count").with_payload(p20_payload.merge(value: 2))
          .and emit_notification("delayed.job.working_count").with_payload(p20_payload.merge(value: 2))
          .and emit_notification("delayed.job.workable_count").with_payload(p20_payload.merge(value: 2))
          .and emit_notification("delayed.job.max_age").with_payload(p20_payload.merge(value: 4.hours))
          .and emit_notification("delayed.job.max_lock_age").with_payload(p20_payload.merge(value: 11.minutes))
          .and emit_notification("delayed.job.workable_count").with_payload(p20_payload.merge(value: 1, queue: 'banana'))
          .and emit_notification("delayed.job.max_age").with_payload(p20_payload.merge(value: 4.hours, queue: 'banana'))
      end
    end

    context 'when worker queues are specified' do
      around do |example|
        Delayed::Worker.queues = %w(banana gram)
        Delayed::Priority.names = { interactive: 0 } # avoid splitting by priority for simplicity
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
          .and emit_notification("delayed.job.count").with_payload(banana_payload.merge(value: 1))
          .and emit_notification("delayed.job.future_count").with_payload(banana_payload.merge(value: 0))
          .and emit_notification("delayed.job.locked_count").with_payload(banana_payload.merge(value: 0))
          .and emit_notification("delayed.job.erroring_count").with_payload(banana_payload.merge(value: 0))
          .and emit_notification("delayed.job.failed_count").with_payload(banana_payload.merge(value: 0))
          .and emit_notification("delayed.job.working_count").with_payload(banana_payload.merge(value: 0))
          .and emit_notification("delayed.job.workable_count").with_payload(banana_payload.merge(value: 1))
          .and emit_notification("delayed.job.max_age").with_payload(banana_payload.merge(value: 4.hours))
          .and emit_notification("delayed.job.max_lock_age").with_payload(banana_payload.merge(value: 0))
          .and emit_notification("delayed.job.count").with_payload(gram_payload.merge(value: 0))
          .and emit_notification("delayed.job.future_count").with_payload(gram_payload.merge(value: 0))
          .and emit_notification("delayed.job.locked_count").with_payload(gram_payload.merge(value: 0))
          .and emit_notification("delayed.job.erroring_count").with_payload(gram_payload.merge(value: 0))
          .and emit_notification("delayed.job.failed_count").with_payload(gram_payload.merge(value: 0))
          .and emit_notification("delayed.job.working_count").with_payload(gram_payload.merge(value: 0))
          .and emit_notification("delayed.job.workable_count").with_payload(gram_payload.merge(value: 0))
          .and emit_notification("delayed.job.max_age").with_payload(gram_payload.merge(value: 0))
          .and emit_notification("delayed.job.max_lock_age").with_payload(gram_payload.merge(value: 0))
      end
    end
  end
end
