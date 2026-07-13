class CreateDelayedLimits < ActiveRecord::Migration[6.0]
  # The `delayed_limits` table backs the `Delayed::Limit` concurrency limiter.
  # (See `Delayed::Limit` for details.)
  #
  # You can delete this migration if you do not intend to use `Delayed::Limit`,
  # but it is safe to leave the table in place.
  def up
    create_table :delayed_limits, primary_key: :purpose, id: :string do |t|
      t.datetime :drained_at, null: false
    end

    return unless connection.adapter_name == 'PostgreSQL'

    # As this is a small, extremely high-churn table, we make it UNLOGGED (the
    # limiter state need not survive a crash) and tune fillfactor/autovacuum to
    # favor in-page [HOT updates](https://www.postgresql.org/docs/current/storage-hot.html).
    execute <<~SQL
      ALTER TABLE delayed_limits SET UNLOGGED;
      ALTER TABLE delayed_limits SET (
        fillfactor = 33,
        autovacuum_vacuum_scale_factor = 0,
        autovacuum_vacuum_threshold = 30
      );
    SQL
  end

  def down
    drop_table :delayed_limits
  end
end
