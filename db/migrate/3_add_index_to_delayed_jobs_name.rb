class AddIndexToDelayedJobsName < ActiveRecord::Migration[6.0]
  include Delayed::Helpers::Migration

  disable_ddl_transaction! if concurrent_index_creation_supported?

  def change
    opts = {}
    opts[:algorithm] = :concurrently if concurrent_index_creation_supported?
    upsert_index :delayed_jobs, :name, **opts
  end
end
