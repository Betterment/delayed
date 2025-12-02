class AddIndexToDelayedJobsName < ActiveRecord::Migration[6.0]
  include Delayed::Helpers::Migration

  # Set to the maximum amount of time you want this migration to run:
  WAIT_TIMEOUT = 5.minutes

  # Concurrent index creation cannot be run inside a transaction:
  disable_ddl_transaction! if concurrent_index_creation_supported?

  def change
    opts = {}

    # Postgres supports creating indexes concurrently, which avoids locking the table
    # while the index is building:
    opts[:algorithm] = :concurrently if concurrent_index_creation_supported?

    upsert_index :delayed_jobs, :name, wait_timeout: WAIT_TIMEOUT, **opts
  end
end
