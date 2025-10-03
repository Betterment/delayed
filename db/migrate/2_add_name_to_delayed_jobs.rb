class AddNameToDelayedJobs < ActiveRecord::Migration[6.0]
  def change
    add_column :delayed_jobs, :name, :string, null: true
  end
end
