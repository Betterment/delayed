# frozen_string_literal: true

class RequireRunAtAndName < ActiveRecord::Migration[6.0]
  def up
    # Belt-and-braces backfill before adding the constraints. The old
    # before_save hook always ran on the supported enqueue path, so under
    # normal operation no rows should have NULL here - but legacy data from
    # other sources (manual SQL, undocumented .create! calls) might.
    execute <<~SQL.squish
      UPDATE delayed_jobs SET run_at = COALESCE(created_at, CURRENT_TIMESTAMP) WHERE run_at IS NULL
    SQL
    execute <<~SQL.squish
      UPDATE delayed_jobs SET name = 'Delayed::Job' WHERE name IS NULL
    SQL

    change_column_null :delayed_jobs, :run_at, false
    change_column_null :delayed_jobs, :name, false
  end

  def down
    change_column_null :delayed_jobs, :run_at, true
    change_column_null :delayed_jobs, :name, true
  end
end
