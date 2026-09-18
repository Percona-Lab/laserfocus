class CreateDiscoveryIdeas < ActiveRecord::Migration[8.1]
  def change
    create_table :discovery_ideas do |t|
      t.string   :jira_key, null: false
      t.string   :summary, null: false
      t.string   :horizon, null: false
      t.string   :incubator_status
      t.string   :rank
      t.json     :raw_fields
      t.datetime :last_seen_in_query_at
      t.datetime :removed_at
      t.timestamps
    end
    add_index :discovery_ideas, :jira_key, unique: true
    add_index :discovery_ideas, :horizon
    add_index :discovery_ideas, :removed_at

    # Delivery targets are referenced by Jira key rather than by epic id: a JPD
    # idea can point at a Story, or at an epic this board does not track.
    create_table :idea_deliveries do |t|
      t.references :discovery_idea, null: false, foreign_key: true
      t.string :jira_key, null: false
      t.string :issue_type
      t.timestamps
    end
    add_index :idea_deliveries, :jira_key
    add_index :idea_deliveries, [ :discovery_idea_id, :jira_key ], unique: true
  end
end
