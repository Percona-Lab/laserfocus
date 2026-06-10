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

  test "normalizes labels and component names from raw fields" do
    issue = Issue.create!(
      jira_key: "PG-11", epic: @epic,
      issue_type: "Task", summary: "Do it too",
      jira_status: "To Do",
      raw_fields: {
        "labels" => [ "backend", "", nil ],
        "components" => [ { "name" => "API" }, { "name" => "" }, "Docs" ]
      }
    )

    assert_equal [ "backend" ], issue.labels
    assert_equal [ "API", "Docs" ], issue.components
  end
end
