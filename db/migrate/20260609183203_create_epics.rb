class CreateEpics < ActiveRecord::Migration[8.1]
  def change
    create_table :epics do |t|
      t.string :jira_key, null: false
      t.string :name, null: false
      t.integer :priority, null: false, default: 0
      t.string :jira_status, null: false
      t.json :raw_fields
      t.datetime :last_seen_in_query_at
      t.datetime :removed_at

      t.timestamps
    end
    add_index :epics, :jira_key, unique: true
    add_index :epics, :removed_at
  end
end
