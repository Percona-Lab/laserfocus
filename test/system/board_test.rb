require "application_system_test_case"

class BoardSystemTest < ApplicationSystemTestCase
  fixtures :epics, :issues

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
  end

  test "logged-in user sees columns and postits" do
    visit "/auth/google_oauth2/callback"
    visit "/"
    assert_selector ".kb-col", minimum: 2
    assert_selector ".kb-card", minimum: 4, visible: :all
  end

  test "epic name in column header links to its jira epic" do
    visit "/auth/google_oauth2/callback"
    visit "/"
    link = find(".kb-col[data-epic-key='PG-1'] a.kb-col-name")
    assert_equal "https://example.atlassian.net/browse/PG-1", link["href"]
    assert_equal "_blank", link["target"]
  end

  test "epic name link is absent for the unplanned column" do
    Issue.where(epic_id: nil).delete_all
    orphan = Issue.create!(
      jira_key: "PG-99", epic: nil, issue_type: "Task",
      summary: "Orphan task", jira_status: "In Progress",
      status_changed_at_jira: 1.day.ago, created_at_jira: 1.day.ago
    )
    visit "/auth/google_oauth2/callback"
    visit "/"
    assert_selector ".kb-col[data-epic-key='UNPLANNED'] span.kb-col-name"
    assert_no_selector ".kb-col[data-epic-key='UNPLANNED'] a.kb-col-name"
  ensure
    orphan&.destroy
  end
end
