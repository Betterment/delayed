# frozen_string_literal: true

class AddRunAtAndNameNotNullCheck < ActiveRecord::Migration[6.0]
  CONSTRAINTS = {
    run_at: 'chk_delayed_jobs_run_at_not_null',
    name: 'chk_delayed_jobs_name_not_null',
  }.freeze

  def up
    return unless postgres?

    CONSTRAINTS.each do |column, name|
      execute <<~SQL.squish
        ALTER TABLE delayed_jobs
          ADD CONSTRAINT #{name}
          CHECK (#{column} IS NOT NULL) NOT VALID
      SQL
    end
  end

  def down
    return unless postgres?

    CONSTRAINTS.each_value do |name|
      execute "ALTER TABLE delayed_jobs DROP CONSTRAINT IF EXISTS #{name}"
    end
  end

  private

  def postgres?
    connection.adapter_name == 'PostgreSQL'
  end
end
