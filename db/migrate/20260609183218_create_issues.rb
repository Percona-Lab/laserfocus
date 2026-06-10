class CreateIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :issues do |t|
      t.string :jira_key, null: false
      t.references :epic, foreign_key: true
      t.string :issue_type, null: false
      t.string :summary, null: false
      t.string :jira_status, null: false
      t.string :assignee_username
      t.integer :priority
      t.datetime :created_at_jira
      t.datetime :status_changed_at_jira
      t.json :raw_fields
      t.datetime :last_seen_in_query_at
      t.datetime :removed_at

      t.timestamps
    end
    add_index :issues, :jira_key, unique: true
    add_index :issues, :removed_at
    add_index :issues, :jira_status
  end
end
