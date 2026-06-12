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
end
