require "application_system_test_case"

class BoardLiveUpdateTest < ApplicationSystemTestCase
  fixtures :epics, :issues, :sync_runs

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    visit "/auth/google_oauth2/callback"
    visit "/"
    assert_selector "main.kb-board#board-root"
  end

  test "new issue card appears after broadcast without reload" do
    assert_no_selector %([data-tooltip-id="PG-99"]), visible: :all

    Issue.create!(
      jira_key: "PG-99",
      epic: epics(:priority_one),
      issue_type: "Task",
      summary: "Brand new task",
      jira_status: "In Progress",
      status_changed_at_jira: 1.day.ago,
      created_at_jira: 1.day.ago
    )
    broadcast_board

    assert_selector %([data-tooltip-id="PG-99"]), visible: :all
  end

  test "removed issue card disappears after broadcast without reload" do
    assert_selector %([data-tooltip-id="PG-10"]), visible: :all

    issues(:fresh_in_progress).update!(removed_at: Time.current)
    broadcast_board

    assert_no_selector %([data-tooltip-id="PG-10"]), visible: :all
  end

  test "staleness transitions are reflected on existing card after broadcast" do
    assert_selector %([data-tooltip-id="PG-10"][data-staleness="fresh"]), visible: :all

    issues(:fresh_in_progress).update!(status_changed_at_jira: 5.days.ago)
    broadcast_board
    assert_selector %([data-tooltip-id="PG-10"][data-staleness="somewhat"]), visible: :all

    issues(:fresh_in_progress).update!(status_changed_at_jira: 20.days.ago)
    broadcast_board
    assert_selector %([data-tooltip-id="PG-10"][data-staleness="really"]), visible: :all
  end

  test "new epic column appears after broadcast without reload" do
    assert_no_selector %(.kb-col[data-epic-key="PG-77"])

    epic = Epic.create!(
      jira_key: "PG-77", name: "Fresh Epic",
      priority: 50, jira_status: "In Progress"
    )
    Issue.create!(
      jira_key: "PG-770", epic: epic, issue_type: "Task",
      summary: "child of fresh epic", jira_status: "In Progress",
      status_changed_at_jira: 1.day.ago, created_at_jira: 1.day.ago
    )
    broadcast_board

    assert_selector %(.kb-col[data-epic-key="PG-77"])
    assert_selector %([data-tooltip-id="PG-770"]), visible: :all
  end

  test "removed epic column disappears after broadcast without reload" do
    assert_selector %(.kb-col[data-epic-key="PG-1"])

    epics(:priority_one).update!(removed_at: Time.current)
    broadcast_board

    assert_no_selector %(.kb-col[data-epic-key="PG-1"])
  end

end
