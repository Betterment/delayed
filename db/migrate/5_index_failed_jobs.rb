class IndexFailedJobs < ActiveRecord::Migration[6.0]
  include Delayed::Helpers::Migration

  # Set to the maximum amount of time you want this migration to run:
  WAIT_TIMEOUT = 5.minutes

  # Concurrent index creation cannot be run inside a transaction:
  disable_ddl_transaction! if concurrent_index_creation_supported?

  def change
    # You can delete this migration if your database does not support partial indexes.
    return unless connection.supports_partial_index?

    # Postgres supports creating indexes concurrently, which avoids locking the table
    # while the index is building:
    opts = {}
    opts[:algorithm] = :concurrently if concurrent_index_creation_supported?

    # If partial indexes are supported, then the "live" index does not cover failed jobs.
    # To aid in monitoring, this adds a separate (smaller) index for failed jobs:
    opts.merge!(name: 'idx_delayed_jobs_failed', where: 'failed_at IS NOT NULL')

    # Set wait_timeout to the maximum amount of time you want this migration to run:
    upsert_index :delayed_jobs, %i(priority queue), wait_timeout: WAIT_TIMEOUT, **opts
  end
end
