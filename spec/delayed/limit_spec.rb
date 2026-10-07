# frozen_string_literal: true

require 'helper'

RSpec::Matchers.define_negated_matcher :not_change, :change
RSpec::Matchers.define_negated_matcher :not_yield_control, :yield_control
RSpec::Matchers.define_negated_matcher :not_emit_notification, :emit_notification

RSpec.describe Delayed::Limit do
  before do
    skip "Delayed::Limit is not supported on this version of #{current_adapter}" unless described_class.supported?
  end

  after { described_class.delete_all }

  let(:purpose) { :test_bucket }
  let(:limit) { { max: 1, per: 1.second } }
  let(:expected_drain_rate) { 1.second }

  describe '.within_limit' do
    it 'creates a limit row with drained_at set to now + drain_rate' do
      now = Time.now.utc
      expect { |b| described_class.within_limit(purpose, **limit, &b) }
        .to change { described_class.count }.by(1)
        .and yield_control.once

      expect(described_class.first.drained_at).to be_within(0.5.seconds).of(now + expected_drain_rate)
    end

    it 'emits a notification when within the limit' do
      expect { described_class.within_limit(purpose, **limit) { nil } }
        .to emit_notification('delayed.limit.within_limit').with_payload(purpose: purpose)
    end

    context 'with an existing limit row whose drained_at is in the past' do
      before { described_class.create!(purpose: purpose, drained_at: 1.hour.ago) }

      it 'resets drained_at to now + drain_rate (does not accumulate against past time)' do
        now = Time.now.utc
        expect { |b| described_class.within_limit(purpose, **limit, &b) }
          .to yield_control.once
          .and not_change { described_class.count }

        expect(described_class.first.drained_at).to be_within(0.5.seconds).of(now + expected_drain_rate)
      end
    end

    context 'with an existing limit row whose drained_at is in the future' do
      before { described_class.create!(purpose: purpose, drained_at: 10.seconds.from_now) }

      context 'when wait_timeout is within the returned wait time' do
        it 'sleeps for the returned wait time and advances drained_at by drain_rate' do
          expect(described_class).to receive(:sleep).with(a_value_within(1).of(10)).once

          expect { described_class.within_limit(purpose, **limit, wait_timeout: 15.seconds) { raise 'ohno' } }
            .to raise_error(RuntimeError, 'ohno')
            .and change { described_class.first.drained_at }
            .by(a_value_within(0.5).of(expected_drain_rate).and(be_positive))
        end
      end

      context 'when the returned wait time exceeds the wait_timeout' do
        it 'raises LimitExceededError without advancing drained_at' do
          expect { described_class.within_limit(purpose, **limit, wait_timeout: 1.second) { nil } }
            .to raise_error(described_class::LimitExceededError)
            .and not_change { described_class.first.drained_at }
        end

        it 'emits a notification when the limit is exceeded' do
          events = []
          callback = ->(name, *) { events << name }
          ActiveSupport::Notifications.subscribed(callback, 'delayed.limit.exceeded') do
            expect { described_class.within_limit(purpose, **limit, wait_timeout: 1.second) { nil } }
              .to raise_error(described_class::LimitExceededError)
          end
          expect(events).to eq(['delayed.limit.exceeded'])
        end
      end

      context 'when the bucket drains before a subsequent call' do
        it 'succeeds on a later attempt' do
          expect { described_class.within_limit(purpose, **limit, wait_timeout: 1.second) { nil } }
            .to raise_error(described_class::LimitExceededError)

          described_class.where(purpose: purpose).update_all(drained_at: 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations

          now = Time.now.utc
          expect { |b| described_class.within_limit(purpose, **limit, &b) }
            .to yield_control.once

          expect(described_class.first.drained_at).to be_within(0.5.seconds).of(now + expected_drain_rate)
        end
      end
    end

    context 'with a sub-second drain rate (max: 100, per: 1.minute => 0.6s)' do
      let(:limit) { { max: 100, per: 1.minute } }
      let(:expected_drain_rate) { 0.6.seconds }

      it 'creates a limit row with drained_at set 0.6 seconds in the future' do
        now = Time.now.utc
        expect { |b| described_class.within_limit(purpose, **limit, &b) }
          .to change { described_class.count }.by(1)
          .and yield_control.once

        expect(described_class.first.drained_at).to be_within(0.5.seconds).of(now + expected_drain_rate)
      end

      context 'with an existing limit row whose drained_at is in the future' do
        before { described_class.create!(purpose: purpose, drained_at: 1.minute.from_now) }

        context 'when wait_timeout is within the returned wait time' do
          it 'sleeps for the returned wait time and advances drained_at by drain_rate' do
            expect(described_class).to receive(:sleep).with(a_value_within(1).of(60)).once

            expect { described_class.within_limit(purpose, **limit, wait_timeout: 2.minutes) { raise 'ohno' } }
              .to raise_error(RuntimeError, 'ohno')
              .and change { described_class.first.drained_at }
              .by(a_value_within(0.5).of(expected_drain_rate).and(be_positive))
          end
        end

        context 'when the returned wait time exceeds the wait_timeout' do
          it 'raises LimitExceededError without advancing drained_at' do
            expect { described_class.within_limit(purpose, **limit, wait_timeout: 1.second) { nil } }
              .to raise_error(described_class::LimitExceededError)
              .and not_change { described_class.first.drained_at }
          end
        end
      end
    end

    context 'when called inside a database transaction' do
      it 'raises TransactionOpenError without reserving capacity or yielding' do
        expect { |b| described_class.transaction { described_class.within_limit(purpose, **limit, &b) } }
          .to raise_error(described_class::TransactionOpenError, /inside a database transaction/)
          .and not_change { described_class.count }
          .and not_yield_control
      end

      it 'raises before the transaction is materialized (no SQL is sent)' do
        expect { described_class.transaction { described_class.within_limit(purpose, **limit) { nil } } }
          .to raise_error(described_class::TransactionOpenError)
          .and not_emit_notification('sql.active_record')
      end
    end

    context 'when the only open transaction is non-joinable' do
      it 'does not raise, and reserves capacity as usual' do
        expect { |b| described_class.transaction(joinable: false) { described_class.within_limit(purpose, **limit, &b) } }
          .to yield_control.once

        expect(described_class.count).to eq(1)
      end

      it 'still raises when application code opens a nested transaction' do
        expect { |b| described_class.transaction(joinable: false) { described_class.transaction { described_class.within_limit(purpose, **limit, &b) } } }
          .to raise_error(described_class::TransactionOpenError)
          .and not_yield_control
      end
    end

    context "under Rails' transactional test harness" do
      # Opens the per-example transaction the same way ActiveRecord::TestFixtures does
      # (via the connection pool on Rails 7.2+, and directly on the connection before that).
      around do |example|
        pool = described_class.connection_pool
        if pool.respond_to?(:pin_connection!)
          pool.pin_connection!(true)
          begin
            example.run
          ensure
            pool.unpin_connection!
          end
        else
          connection = described_class.connection
          connection.begin_transaction(joinable: false, _lazy: false)
          begin
            example.run
          ensure
            connection.rollback_transaction
          end
        end
      end

      it 'does not raise, and reserves capacity as usual' do
        expect(described_class.connection.transaction_open?).to be(true)

        expect { |b| described_class.within_limit(purpose, **limit, &b) }
          .to yield_control.once

        expect(described_class.count).to eq(1)
      end

      it 'still raises when the code under test opens a transaction' do
        expect { |b| described_class.transaction { described_class.within_limit(purpose, **limit, &b) } }
          .to raise_error(described_class::TransactionOpenError)
          .and not_yield_control
      end
    end

    context 'when Delayed::Limit has its own connection pool' do
      around do |example|
        config = if ActiveRecord::Base.respond_to?(:connection_db_config)
          ActiveRecord::Base.connection_db_config.configuration_hash
        else
          ActiveRecord::Base.connection_config
        end
        described_class.establish_connection(config)
        example.run
      ensure
        described_class.remove_connection
      end

      it 'uses a separate pool from the application' do
        expect(described_class.connection_pool).not_to equal(ActiveRecord::Base.connection_pool)
      end

      it 'does not treat a transaction on the application pool as an open transaction' do
        expect { |b| ActiveRecord::Base.transaction { described_class.within_limit(purpose, **limit, &b) } }
          .to yield_control.once
          .and change { described_class.count }.by(1)
      end

      it 'still raises for a transaction on its own pool' do
        expect { |b| described_class.transaction { described_class.within_limit(purpose, **limit, &b) } }
          .to raise_error(described_class::TransactionOpenError)
          .and not_yield_control
      end
    end

    context 'with a limit registered in advance via .register!' do
      before { allow(described_class).to receive(:limits).and_return(purpose => limit) }

      it 'looks up the limit by purpose without requiring max/per' do
        now = Time.now.utc
        expect { |b| described_class.within_limit(purpose, &b) }
          .to change { described_class.count }.by(1)
          .and yield_control.once

        expect(described_class.first.drained_at).to be_within(0.5.seconds).of(now + expected_drain_rate)
      end

      context 'when max and per are also passed directly' do
        it 'raises ArgumentError without reserving capacity' do
          expect { described_class.within_limit(purpose, **limit) { nil } }
            .to raise_error(ArgumentError, /already registered/)
            .and not_change { described_class.count }
        end
      end
    end
  end

  describe '.register!' do
    around do |example|
      original_limits = described_class.limits.dup
      example.run
    ensure
      described_class.instance_variable_set(:@limits, original_limits)
    end

    it 'registers a policy that can be looked up' do
      described_class.register!(:some_purpose, max: 10, per: 1.minute)

      expect(described_class.limits.fetch(:some_purpose)).to eq(max: 10, per: 1.minute)
    end

    it 'is a no-op when re-registering a purpose with an identical config' do
      described_class.register!(:some_purpose, max: 10, per: 1.minute)

      expect { described_class.register!(:some_purpose, max: 10, per: 1.minute) }
        .not_to change { described_class.limits.fetch(:some_purpose) }
        .from(max: 10, per: 1.minute)
    end

    it 'raises when a policy is already registered with a conflicting config' do
      described_class.register!(:some_purpose, max: 10, per: 1.minute)

      expect { described_class.register!(:some_purpose, max: 5, per: 1.second) }
        .to raise_error(ArgumentError, /already registered and does not match/)
    end
  end
end
