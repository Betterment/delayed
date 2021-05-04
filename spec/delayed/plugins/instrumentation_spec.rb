require 'helper'

RSpec.describe Delayed::Plugins::Instrumentation do
  let!(:job) { Delayed::Job.enqueue SimpleJob.new, priority: 13, queue: 'test' }

  it 'emits delayed.job.run' do
    expect { Delayed::Worker.new.work_off }.to emit_notification('delayed.job.run').with_payload(
      job_name: 'SimpleJob',
      priority: 13,
      queue: 'test',
      table: 'delayed_jobs',
      database: current_database,
      database_adapter: current_adapter,
      job: job,
    )
  end

  context 'when the job errors' do
    let!(:job) { Delayed::Job.enqueue ErrorJob.new, priority: 7, queue: 'foo' }

    it 'emits delayed.job.error' do
      expect { Delayed::Worker.new.work_off }.to emit_notification('delayed.job.error').with_payload(
        job_name: 'ErrorJob',
        priority: 7,
        queue: 'foo',
        table: 'delayed_jobs',
        database: current_database,
        database_adapter: current_adapter,
        job: job,
      )
    end
  end

  context 'when the job fails' do
    let!(:job) { Delayed::Job.enqueue FailureJob.new, priority: 3, queue: 'bar' }

    it 'emits delayed.job.failure' do
      expect { Delayed::Worker.new.work_off }.to emit_notification('delayed.job.failure').with_payload(
        job_name: 'FailureJob',
        priority: 3,
        queue: 'bar',
        table: 'delayed_jobs',
        database: current_database,
        database_adapter: current_adapter,
        job: job,
      )
    end
  end
end
