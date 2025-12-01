class IndexLiveJobs < ActiveRecord::Migration[6.0]
  include Delayed::Helpers::Migration

  # Concurrent index creation cannot be run inside a transaction:
  disable_ddl_transaction! if concurrent_index_creation_supported?

  def change
    opts = {}
    columns = %i(priority run_at queue)

    # Postgres supports creating indexes concurrently,
    # which avoids locking the table while the index is building:
    opts[:algorithm] = :concurrently if concurrent_index_creation_supported?

    if connection.supports_partial_index?
      # Postgres and SQLite both support partial indexes, allowing us to pre-filter out failed jobs:
      opts[:where] = 'failed_at IS NULL'
    else
      # If partial indexes aren't supported, failed_at will be included in the primary index:
      columns = %i(failed_at) + columns
    end

    upsert_index :delayed_jobs, columns, **opts.merge(name: 'idx_delayed_jobs_live'), wait_timeout: 5.minutes
  end
end
