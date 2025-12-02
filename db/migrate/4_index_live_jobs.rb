class IndexLiveJobs < ActiveRecord::Migration[6.0]
  include Delayed::Helpers::Migration

  # Set to the maximum amount of time you want this migration to run:
  WAIT_TIMEOUT = 5.minutes

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

    upsert_index :delayed_jobs, columns, wait_timeout: WAIT_TIMEOUT, name: 'idx_delayed_jobs_live', **opts
  end
end
