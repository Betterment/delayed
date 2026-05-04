class RemoveLegacyIndex < ActiveRecord::Migration[6.0]
  include Delayed::Helpers::Migration

  disable_ddl_transaction! if concurrent_index_creation_supported?

  def change
    opts = { name: 'delayed_jobs_priority' }
    opts[:algorithm] = :concurrently if concurrent_index_creation_supported?

    remove_index_if_exists :delayed_jobs, %i(priority run_at), **opts, wait_timeout: 5.minutes
  end
end
