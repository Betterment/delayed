class IndexFailedJobs < ActiveRecord::Migration[6.0]
  # Concurrent index creation cannot be run inside a transaction:
  disable_ddl_transaction! if connection.index_algorithms.key?(:concurrently)

  def change
    # You can delete this migration if your database does not support partial indexes.
    return unless connection.supports_partial_index?

    # Postgres supports creating indexes concurrently, which avoids locking the table
    # while the index is building:
    opts = {}
    opts[:algorithm] = :concurrently if connection.index_algorithms.key?(:concurrently)

    # If partial indexes are supported, then the "live" index does not cover failed jobs.
    # To aid in monitoring, this adds a separate (smaller) index for failed jobs:
    opts.merge!(name: 'idx_delayed_jobs_failed', where: 'failed_at IS NOT NULL')
    add_index :delayed_jobs, %i(priority queue), **opts
  end
end
