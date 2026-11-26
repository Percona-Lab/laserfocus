class CreateRepoExclusions < ActiveRecord::Migration[8.1]
  def change
    create_table :repo_exclusions do |t|
      t.string :user_email, null: false
      t.string :repo, null: false
      t.timestamps
    end
    add_index :repo_exclusions, [ :user_email, :repo ], unique: true
  end
end
