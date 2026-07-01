class AddProvisionalToIssues < ActiveRecord::Migration[8.1]
  def change
    add_column :issues, :provisional, :boolean, null: false, default: false
  end
end
