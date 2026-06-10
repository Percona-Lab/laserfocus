class CreateSyncRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_runs do |t|
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.boolean :ok, null: false, default: false
      t.text :error_message
      t.integer :fetched_count, null: false, default: 0

      t.timestamps
    end
  end
end
