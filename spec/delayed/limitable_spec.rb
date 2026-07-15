# frozen_string_literal: true

require 'helper'

RSpec.describe Delayed::Limitable do
  let(:purpose) { :limitable_spec }

  around do |example|
    original_limits = Delayed::Limit.limits
    example.run
  ensure
    Delayed::Limit.instance_variable_set(:@limits, original_limits)
  end

  before do
    allow(Delayed::Limit).to receive(:within_limit).and_yield
  end

  it 'is automatically included in ActiveJob classes' do
    expect(ActiveJob::Base).to respond_to(:with_limit)
  end

  describe '.with_limit' do
    context 'when on: is not specified' do
      let(:job_class) do
        p = purpose
        Class.new(ActiveJob::Base) do
          with_limit p, max: 4, per: 1.second

          define_method(:perform) { :result }
        end
      end

      it 'wraps perform with within_limit' do
        job_class.new.perform
        expect(Delayed::Limit).to have_received(:within_limit)
          .with(purpose, wait_timeout: 5.seconds).once
      end

      it 'registers the limit policy with Delayed::Limit' do
        job_class
        expect(Delayed::Limit.limits.fetch(purpose)).to eq(max: 4, per: 1.second)
      end
    end

    context 'when purpose is not specified' do
      let(:job_class) do
        Class.new(ActiveJob::Base) do
          define_method(:perform) { :result }
        end
      end

      before do
        stub_const('LimitableDefaultPurposeJob', job_class)
        job_class.with_limit(max: 4, per: 1.second)
      end

      it 'defaults the purpose to the underscored class name' do
        job_class.new.perform
        expect(Delayed::Limit).to have_received(:within_limit)
          .with(:limitable_default_purpose_job, wait_timeout: 5.seconds).once
      end
    end

    context 'when wait_timeout: is specified' do
      let(:job_class) do
        p = purpose
        Class.new(ActiveJob::Base) do
          with_limit p, max: 4, per: 1.second, wait_timeout: 30.seconds

          define_method(:perform) { :result }
        end
      end

      it 'passes the wait_timeout through to within_limit' do
        job_class.new.perform
        expect(Delayed::Limit).to have_received(:within_limit)
          .with(purpose, wait_timeout: 30.seconds).once
      end
    end

    context 'when on: is a single method name' do
      let(:job_class) do
        p = purpose
        Class.new(ActiveJob::Base) do
          with_limit p, max: 4, per: 1.second, on: :do_work

          define_method(:perform) { do_work && dont_do_work }
          define_method(:do_work) { :result_b }
          define_method(:dont_do_work) { :result_a }
        end
      end

      it 'wraps the specified method with within_limit' do
        job_class.new.do_work
        expect(Delayed::Limit).to have_received(:within_limit)
          .with(purpose, wait_timeout: 5.seconds).once
      end

      it 'does not add an extra within_limit call when perform delegates to the wrapped method' do
        job_class.new.perform
        expect(Delayed::Limit).to have_received(:within_limit).once
      end
    end

    context 'when on: is an array of method names' do
      let(:job_class) do
        p = purpose
        Class.new(ActiveJob::Base) do
          with_limit p, max: 4, per: 1.second, on: %i(do_work_a do_work_b)

          def perform; end
          define_method(:do_work_a) { :result_a }
          define_method(:do_work_b) { :result_b }
        end
      end

      it 'wraps each named method with within_limit' do
        job_class.new.tap do |job|
          job.perform
          job.do_work_a
          job.do_work_b
        end
        expect(Delayed::Limit).to have_received(:within_limit)
          .with(purpose, wait_timeout: 5.seconds).twice
      end
    end

    context 'when the purpose was registered in advance and no config is given' do
      before { Delayed::Limit.register!(purpose, max: 4, per: 1.second) }

      let(:job_class) do
        p = purpose
        Class.new(ActiveJob::Base) do
          with_limit p

          define_method(:perform) { :result }
        end
      end

      it 'references the registered limit by purpose' do
        job_class.new.perform
        expect(Delayed::Limit).to have_received(:within_limit)
          .with(purpose, wait_timeout: 5.seconds).once
      end
    end

    context 'when the config contains an unknown key' do
      it 'raises ArgumentError' do
        p = purpose
        expect {
          Class.new(ActiveJob::Base) { with_limit p, max: 4, per: 1.second, wait_timout: 1.second }
        }.to raise_error(ArgumentError, /wait_timout/)
      end
    end

    context 'when with_limit is declared multiple times' do
      let(:other_purpose) { :"#{purpose}_b" }

      let(:job_class) do
        p = purpose
        other = other_purpose
        Class.new(ActiveJob::Base) do
          with_limit p, max: 4, per: 1.second, wait_timeout: 100.seconds, on: :do_work_a, retry_jitter: 0
          with_limit other, max: 2, per: 1.minute, wait_timeout: 30.seconds, on: :do_work_b, retry_jitter: 0

          define_method(:perform) { raise Delayed::Limit::LimitExceededError }
          define_method(:do_work_a) { :result_a }
          define_method(:do_work_b) { :result_b }
        end
      end

      before { stub_const('LimitableMultipleLimitsJob', job_class) }

      it 'registers each limit policy' do
        job_class
        expect(Delayed::Limit.limits.fetch(purpose)).to eq(max: 4, per: 1.second)
        expect(Delayed::Limit.limits.fetch(other_purpose)).to eq(max: 2, per: 1.minute)
      end

      it 'wraps each method with its own limit' do
        job_class.new.tap do |job|
          job.do_work_a
          job.do_work_b
        end
        expect(Delayed::Limit).to have_received(:within_limit)
          .with(purpose, wait_timeout: 100.seconds).once
        expect(Delayed::Limit).to have_received(:within_limit)
          .with(other_purpose, wait_timeout: 30.seconds).once
      end

      it 'defines only a single retry handler' do
        handlers = job_class.rescue_handlers.select do |class_name, _|
          class_name == Delayed::Limit::LimitExceededError.name
        end
        expect(handlers.size).to eq(1)
      end

      it 'retries according to the first declaration (its wait_timeout floors the retry wait)' do
        job = job_class.new
        allow(job).to receive(:retry_job)
        job.perform_now
        expect(job).to have_received(:retry_job)
          .with(a_hash_including(wait: 100.seconds))
      end
    end

    context 'when included in a plain (non-ActiveJob) class' do
      let(:klass) do
        p = purpose
        Class.new do
          include Delayed::Limitable

          with_limit p, max: 4, per: 1.second, on: :do_work

          define_method(:do_work) { :result }
        end
      end

      it 'wraps the specified method with within_limit' do
        expect(klass.new.do_work).to eq(:result)
        expect(Delayed::Limit).to have_received(:within_limit)
          .with(purpose, wait_timeout: 5.seconds).once
      end

      it 'registers the limit policy with Delayed::Limit' do
        klass
        expect(Delayed::Limit.limits.fetch(purpose)).to eq(max: 4, per: 1.second)
      end

      it 'leaves LimitExceededError handling to the caller' do
        allow(Delayed::Limit).to receive(:within_limit).and_raise(Delayed::Limit::LimitExceededError)
        expect { klass.new.do_work }.to raise_error(Delayed::Limit::LimitExceededError)
      end
    end
  end

  describe 'retry behavior' do
    let(:job_class) do
      p = purpose
      Class.new(ActiveJob::Base) do
        with_limit p, max: 4, per: 1.second, retry_jitter: 0

        define_method(:perform) { raise Delayed::Limit::LimitExceededError }
      end
    end

    before { stub_const('LimitableRetryJob', job_class) }

    it 'retries the job when the limit is exceeded' do
      job = job_class.new
      allow(job).to receive(:retry_job)
      job.perform_now
      expect(job).to have_received(:retry_job)
        .with(a_hash_including(wait: a_value > 0, error: an_instance_of(Delayed::Limit::LimitExceededError)))
    end

    it 'floors the retry wait at the wait_timeout' do
      job = job_class.new
      allow(job).to receive(:retry_job)
      job.perform_now
      expect(job).to have_received(:retry_job)
        .with(a_hash_including(wait: 5.seconds))
    end

    context 'when a custom wait: is specified' do
      let(:job_class) do
        p = purpose
        Class.new(ActiveJob::Base) do
          with_limit p, max: 4, per: 1.second, retry_wait: ->(_attempts) { 123 }

          define_method(:perform) { raise Delayed::Limit::LimitExceededError }
        end
      end

      it 'uses the custom wait' do
        job = job_class.new
        allow(job).to receive(:retry_job)
        job.perform_now
        expect(job).to have_received(:retry_job)
          .with(a_hash_including(wait: 123))
      end
    end

    context 'when retry_attempts: is specified' do
      let(:job_class) do
        p = purpose
        Class.new(ActiveJob::Base) do
          with_limit p, max: 4, per: 1.second, retry_attempts: 1

          define_method(:perform) { raise Delayed::Limit::LimitExceededError }
        end
      end

      it 'stops retrying once the attempts are exhausted' do
        job = job_class.new
        allow(job).to receive(:retry_job)
        expect { job.perform_now }.to raise_error(Delayed::Limit::LimitExceededError)
        expect(job).not_to have_received(:retry_job)
      end
    end
  end
end
