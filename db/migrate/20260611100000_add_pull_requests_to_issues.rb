class AddPullRequestsToIssues < ActiveRecord::Migration[8.1]
  def change
    add_column :issues, :pull_requests, :json, default: []
  end
end
