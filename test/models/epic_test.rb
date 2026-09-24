require "test_helper"

class EpicTest < ActiveSupport::TestCase
  test "active scope excludes removed epics" do
    Issue.delete_all
    Epic.delete_all
    active  = Epic.create!(jira_key: "PG-1", name: "A", priority: 1, jira_status: "To Do")
    removed = Epic.create!(jira_key: "PG-2", name: "B", priority: 2, jira_status: "Done",
                           removed_at: Time.current)
    assert_includes Epic.active, active
    assert_not_includes Epic.active, removed
  end

  test "ordered scope sorts by creation order, ignoring priority" do
    Issue.delete_all
    Epic.delete_all
    old_low  = Epic.create!(jira_key: "PG-3", name: "Charlie", priority: 9, jira_status: "To Do", created_at: 3.days.ago)
    new_high = Epic.create!(jira_key: "PG-1", name: "Alpha",   priority: 1, jira_status: "To Do", created_at: 1.day.ago)
    assert_equal [ old_low, new_high ], Epic.ordered.to_a
  end

  test "labels come back from raw_fields, empty when absent" do
    assert_equal [], Epic.new.labels
    assert_equal %w[Ongoing pg_tde],
                 Epic.new(raw_fields: { "labels" => [ "Ongoing", "pg_tde", "" ] }).labels
  end

  test "ongoing? matches the configured label only" do
    epic = Epic.new(raw_fields: { "labels" => [ "Ongoing" ] })
    assert epic.ongoing?("Ongoing")
    refute epic.ongoing?("Backlog")
    refute epic.ongoing?(nil)
  end

  test "labelled? matches any label in a list" do
    epic = Epic.new(raw_fields: { "labels" => [ "Community" ] })
    assert epic.labelled?(%w[Ongoing Community])
    assert epic.ongoing?(%w[Ongoing Community])
    refute epic.labelled?([ "Ongoing", nil ])
    refute epic.labelled?([])
  end

  test "status_category reads Jira's coarse bucket" do
    assert_nil Epic.new.status_category
    epic = Epic.new(raw_fields: { "status" => { "statusCategory" => { "key" => "indeterminate" } } })
    assert_equal "indeterminate", epic.status_category
    assert epic.in_progress?
  end
end
