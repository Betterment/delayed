# frozen_string_literal: true

class BackfillNullRunAtAndName < ActiveRecord::Migration[6.0]
  def up
    Delayed::Job.where(run_at: nil).update_all('run_at = COALESCE(created_at, CURRENT_TIMESTAMP)')
    Delayed::Job.where(name: nil).update_all(name: 'Delayed::Job')
  end

  def down
    # Backfill is one-way; cannot restore NULLs.
  end
end
