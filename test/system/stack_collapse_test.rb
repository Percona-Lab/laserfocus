require "application_system_test_case"

class StackCollapseTest < ApplicationSystemTestCase
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

  # PG-1 column: PG-10 (In Progress), PG-11 (In Review), PG-12 (To Do), PG-13 (Done)

  test "middle section toggle hides its cards" do
    within ".kb-col[data-epic-key='PG-1']" do
      assert_selector "[data-tooltip-id='PG-10']"
      find("[data-stack-target='middleBtn'][data-status='in_progress']").click
      assert_no_selector "[data-tooltip-id='PG-10']"
    end
  end

  test "clicking a collapsed middle toggle reveals its cards" do
    within ".kb-col[data-epic-key='PG-1']" do
      find("[data-stack-target='middleBtn'][data-status='in_progress']").click
      assert_no_selector "[data-tooltip-id='PG-10']"
      find("[data-stack-target='middleBtn'][data-status='in_progress']").click
      assert_selector "[data-tooltip-id='PG-10']"
    end
  end

  test "collapse-all button hides all middle sections" do
    within ".kb-col[data-epic-key='PG-1']" do
      assert_selector "[data-tooltip-id='PG-10']"
      assert_selector "[data-tooltip-id='PG-11']"
      find("[data-stack-target='collapseAllBtn']").click
      assert_no_selector "[data-tooltip-id='PG-10']"
      assert_no_selector "[data-tooltip-id='PG-11']"
    end
  end

  test "collapse-all then expand-all restores middle sections" do
    within ".kb-col[data-epic-key='PG-1']" do
      find("[data-stack-target='collapseAllBtn']").click
      assert_no_selector "[data-tooltip-id='PG-10']"
      find("[data-stack-target='collapseAllBtn']").click
      assert_selector "[data-tooltip-id='PG-10']"
      assert_selector "[data-tooltip-id='PG-11']"
    end
  end

  test "middle collapse state survives a Turbo broadcast" do
    within ".kb-col[data-epic-key='PG-1']" do
      find("[data-stack-target='middleBtn'][data-status='in_progress']").click
      assert_no_selector "[data-tooltip-id='PG-10']"
    end

    Issue.create!(
      jira_key: "PG-78", epic: epics(:priority_two), summary: "Broadcast marker",
      jira_status: "In Progress", issue_type: "Task",
      created_at_jira: Time.current, status_changed_at_jira: Time.current
    )
    broadcast_board

    assert_selector "[data-tooltip-id='PG-78']", visible: :all

    within ".kb-col[data-epic-key='PG-1']" do
      assert_no_selector "[data-tooltip-id='PG-10']"
      assert_selector "[data-tooltip-id='PG-11']"
    end
  end

end
