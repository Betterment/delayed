# frozen_string_literal: true

class ValidateRunAtAndNameNotNull < ActiveRecord::Migration[6.0]
  CONSTRAINTS = {
    run_at: 'chk_delayed_jobs_run_at_not_null',
    name: 'chk_delayed_jobs_name_not_null',
  }.freeze

  def up
    CONSTRAINTS.each do |column, name|
      if postgres?
        execute "ALTER TABLE delayed_jobs VALIDATE CONSTRAINT #{name}"
        change_column_null :delayed_jobs, column, false
        execute "ALTER TABLE delayed_jobs DROP CONSTRAINT #{name}"
      else
        change_column_null :delayed_jobs, column, false
      end
    end
  end

  def down
    CONSTRAINTS.each do |column, name|
      if postgres?
        change_column_null :delayed_jobs, column, true
        execute <<~SQL.squish
          ALTER TABLE delayed_jobs
            ADD CONSTRAINT #{name}
            CHECK (#{column} IS NOT NULL) NOT VALID
        SQL
      else
        change_column_null :delayed_jobs, column, true
      end
    end
  end

  private

  def postgres?
    connection.adapter_name == 'PostgreSQL'
  end
end
