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

  test "ordered scope sorts by priority asc, name asc" do
    Issue.delete_all
    Epic.delete_all
    c = Epic.create!(jira_key: "PG-3", name: "Charlie", priority: 2, jira_status: "To Do")
    a = Epic.create!(jira_key: "PG-1", name: "Alpha",   priority: 1, jira_status: "To Do")
    b = Epic.create!(jira_key: "PG-2", name: "Bravo",   priority: 1, jira_status: "To Do")
    assert_equal [ a, b, c ], Epic.ordered.to_a
  end
end
