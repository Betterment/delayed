class SetPostgresFillfactor < ActiveRecord::Migration[6.0]
  # On PostgreSQL, we do not index `locked_at` or `locked_by` to optimize for "HOT updates" during pickup.
  # See: https://www.postgresql.org/docs/current/storage-hot.html
  #
  # To increase the odds that a given page has room for a HOT update, we reduce the
  # "fillfactor" (percentage filled by default), and set a more aggressive autovacume target:
  def up
    return unless connection.adapter_name == 'PostgreSQL'

    execute <<~SQL
      ALTER TABLE delayed_jobs SET (
        autovacuum_vacuum_scale_factor = 0.02,
        fillfactor = 33
      );
      ALTER INDEX idx_delayed_jobs_live SET (
        fillfactor = 33
      );
    SQL
  end

  def down
    return unless connection.adapter_name == 'PostgreSQL'

    execute <<~SQL
      ALTER TABLE delayed_jobs
        RESET (autovacuum_vacuum_scale_factor, fillfactor);
      ALTER INDEX idx_delayed_jobs_live
        RESET (fillfactor);
    SQL
  end
end
