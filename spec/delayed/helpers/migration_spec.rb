# frozen_string_literal: true

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

  describe '#upsert_index retry behavior' do
    it 'raises exception when wait_timeout is exceeded based on @migration_start' do
      migration.migration_start = Delayed::Job.db_time_now - 6.minutes

      allow(migration).to receive(:add_index).and_raise(ActiveRecord::LockWaitTimeout)
      allow(migration.connection).to receive(:indexes).and_return([])

      expect {
        migration.upsert_index(:delayed_jobs, :name, wait_timeout: 5.minutes)
      }.to raise_error(ActiveRecord::LockWaitTimeout)
    end

    it 're-checks for invalid index and drops it before retrying after timeout' do
      add_index_calls = 0
      remove_index_calls = 0
      lookup_calls = 0

      invalid_opts = ActiveRecord.version >= Gem::Version.new('7.1.0') ? { valid?: false } : { unique: true }
      invalid_index = instance_double(
        ActiveRecord::ConnectionAdapters::IndexDefinition,
        name: 'test_idx',
        columns: ['name'],
        **invalid_opts,
      )

      allow(migration.connection).to receive(:indexes) do
        lookup_calls += 1
        lookup_calls == 2 ? [invalid_index] : []
      end

      allow(migration).to receive(:add_index) do |*_args|
        add_index_calls += 1
        raise ActiveRecord::StatementTimeout, 'timeout' if add_index_calls == 1
      end

      allow(migration).to receive(:remove_index) do |*_args|
        remove_index_calls += 1
      end

      migration.upsert_index(:delayed_jobs, :name, name: 'test_idx', wait_timeout: 5.minutes)

      expect(lookup_calls).to eq(3)
      expect(remove_index_calls).to eq(1)
      expect(add_index_calls).to eq(2)
    end
  end
end
