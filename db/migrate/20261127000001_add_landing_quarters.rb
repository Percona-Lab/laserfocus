class AddLandingQuarters < ActiveRecord::Migration[8.1]
  def change
    # The internal landing target of an idea and its label.
    add_column :discovery_ideas, :time_id, :integer
    add_column :discovery_ideas, :codename, :string

    # Progress of each delivery ticket, read whether or not its epic is on the
    # board, so an idea can be judged on track, at risk or landed.
    add_column :idea_deliveries, :summary, :string
    add_column :idea_deliveries, :status_name, :string
    add_column :idea_deliveries, :status_category, :string
    add_column :idea_deliveries, :resolved_at, :datetime
    add_column :idea_deliveries, :todo_count, :integer, default: 0, null: false
    add_column :idea_deliveries, :in_progress_count, :integer, default: 0, null: false
    add_column :idea_deliveries, :done_count, :integer, default: 0, null: false

    # Every change to an idea's Time-ID, Codename or roadmap horizon, copied
    # from the Jira changelog, so slips stay visible after the field moves on.
    create_table :idea_events do |t|
      t.string :jira_key, null: false
      t.string :field, null: false
      t.string :from_value
      t.string :to_value
      t.string :author
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :idea_events, [ :jira_key, :occurred_at ]
  end
end
