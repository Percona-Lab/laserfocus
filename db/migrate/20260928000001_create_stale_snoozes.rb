class CreateStaleSnoozes < ActiveRecord::Migration[8.1]
  def change
    create_table :stale_snoozes do |t|
      t.string :jira_key, null: false
      t.string :jira_status, null: false
      t.datetime :snoozed_until, null: false
      t.string :snoozed_by, null: false
      t.string :reason
      t.timestamps
    end
    add_index :stale_snoozes, :jira_key, unique: true
    add_index :stale_snoozes, :snoozed_until
  end
end
