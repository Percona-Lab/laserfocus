class AddJiraIdToIssues < ActiveRecord::Migration[8.1]
  def change
    add_column :issues, :jira_id, :string
  end
end
