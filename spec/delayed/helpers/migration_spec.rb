require 'helper'

describe Delayed::Helpers::Migration do
  let(:migration_class) do
    Class.new(ActiveRecord::Migration[6.0]) do
      include Delayed::Helpers::Migration

      attr_accessor :migration_start

      def connection
        ActiveRecord::Base.connection
      end

      def reversible
        direction = Object.new
        def direction.up
          yield if block_given?
        end

        def direction.down
          yield if block_given?
        end
        yield direction
      end
    end
  end

  let(:migration) { migration_class.new }

  before do
    migration.migration_start = Delayed::Job.db_time_now
  end

  describe '#with_retry_loop timeout tracking' do
    it 'raises exception when wait_timeout is exceeded based on @migration_start' do
      # Simulate migration that started 6 minutes ago
      migration.migration_start = Delayed::Job.db_time_now - 6.minutes

      expect {
        migration.with_retry_loop(wait_timeout: 5.minutes) do
          raise ActiveRecord::LockWaitTimeout
        end
      }.to raise_error(ActiveRecord::LockWaitTimeout)
    end

    it 'continues retrying while within the timeout window' do
      call_count = 0

      # First retry is within timeout, second exceeds it
      allow(Delayed::Job).to receive(:db_time_now).and_return(
        migration.migration_start + 4.minutes, # Within timeout
        migration.migration_start + 6.minutes, # Exceeds timeout
      )

      expect {
        migration.with_retry_loop(wait_timeout: 5.minutes) do
          call_count += 1
          raise ActiveRecord::LockWaitTimeout
        end
      }.to raise_error(ActiveRecord::LockWaitTimeout)

      expect(call_count).to eq(2)
    end
  end
end
