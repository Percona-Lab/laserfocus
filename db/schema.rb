# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_18_000002) do
  create_table "board_orders", force: :cascade do |t|
    t.json "collapsed_columns", default: [], null: false
    t.json "column_order", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "board_snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 0, null: false
  end

  create_table "discovery_ideas", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "horizon", null: false
    t.string "incubator_status"
    t.string "jira_key", null: false
    t.datetime "last_seen_in_query_at"
    t.string "rank"
    t.json "raw_fields"
    t.datetime "removed_at"
    t.string "summary", null: false
    t.datetime "updated_at", null: false
    t.index ["horizon"], name: "index_discovery_ideas_on_horizon"
    t.index ["jira_key"], name: "index_discovery_ideas_on_jira_key", unique: true
    t.index ["removed_at"], name: "index_discovery_ideas_on_removed_at"
  end

  create_table "epic_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "epic_id"
    t.string "event_type", null: false
    t.string "jira_key", null: false
    t.string "name", null: false
    t.datetime "occurred_at", null: false
    t.datetime "updated_at", null: false
    t.index ["epic_id"], name: "index_epic_events_on_epic_id"
    t.index ["jira_key"], name: "index_epic_events_on_jira_key"
    t.index ["occurred_at"], name: "index_epic_events_on_occurred_at"
  end

  create_table "epics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "jira_key", null: false
    t.string "jira_status", null: false
    t.datetime "last_seen_in_query_at"
    t.string "name", null: false
    t.integer "priority", default: 0, null: false
    t.json "raw_fields"
    t.datetime "removed_at"
    t.datetime "updated_at", null: false
    t.index ["jira_key"], name: "index_epics_on_jira_key", unique: true
    t.index ["removed_at"], name: "index_epics_on_removed_at"
  end

  create_table "idea_deliveries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "discovery_idea_id", null: false
    t.string "issue_type"
    t.string "jira_key", null: false
    t.datetime "updated_at", null: false
    t.index ["discovery_idea_id", "jira_key"], name: "index_idea_deliveries_on_discovery_idea_id_and_jira_key", unique: true
    t.index ["discovery_idea_id"], name: "index_idea_deliveries_on_discovery_idea_id"
    t.index ["jira_key"], name: "index_idea_deliveries_on_jira_key"
  end

  create_table "issues", force: :cascade do |t|
    t.string "assignee_username"
    t.datetime "created_at", null: false
    t.datetime "created_at_jira"
    t.integer "epic_id"
    t.string "issue_type", null: false
    t.string "jira_id"
    t.string "jira_key", null: false
    t.string "jira_status", null: false
    t.datetime "last_seen_in_query_at"
    t.integer "priority"
    t.boolean "provisional", default: false, null: false
    t.json "pull_requests", default: []
    t.json "raw_fields"
    t.datetime "removed_at"
    t.datetime "status_changed_at_jira"
    t.string "summary", null: false
    t.datetime "updated_at", null: false
    t.index ["epic_id"], name: "index_issues_on_epic_id"
    t.index ["jira_key"], name: "index_issues_on_jira_key", unique: true
    t.index ["jira_status"], name: "index_issues_on_jira_status"
    t.index ["removed_at"], name: "index_issues_on_removed_at"
  end

  create_table "sync_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "fetched_count", default: 0, null: false
    t.datetime "finished_at"
    t.boolean "ok", default: false, null: false
    t.datetime "started_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_seen_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "idea_deliveries", "discovery_ideas"
  add_foreign_key "issues", "epics"
end
