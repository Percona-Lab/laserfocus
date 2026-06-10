require "test_helper"

class IssueTest < ActiveSupport::TestCase
  setup do
    Issue.delete_all
    Epic.delete_all
    @epic = Epic.create!(jira_key: "PG-1", name: "Epic", priority: 1, jira_status: "To Do")
  end

  test "belongs to epic and exposes raw_fields as json" do
    issue = Issue.create!(
      jira_key: "PG-10", epic: @epic,
      issue_type: "Task", summary: "Do it",
      jira_status: "To Do",
      raw_fields: { "labels" => [ "foo" ] }
    )
    assert_equal "foo", Issue.find(issue.id).raw_fields["labels"].first
  end
end
