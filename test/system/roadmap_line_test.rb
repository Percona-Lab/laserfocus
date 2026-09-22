require "application_system_test_case"

class RoadmapLineTest < ApplicationSystemTestCase
  fixtures :epics, :issues, :sync_runs

  setup do
    DiscoveryIdea.create!(jira_key: "PGR-1", summary: "Nothing in Jira", horizon: "now")

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    visit "/auth/google_oauth2/callback"
    visit "/"
    assert_selector "main.kb-board#board-root"
  end

  test "the findings unfold and fold again on click" do
    assert_no_selector ".kb-roadmap-finding"
    find(".kb-roadmap-head").click
    assert_selector ".kb-roadmap-finding"
    find(".kb-roadmap-head").click
    assert_no_selector ".kb-roadmap-finding"
  end

  test "an open roadmap line survives a Turbo broadcast" do
    find(".kb-roadmap-head").click
    assert_selector ".kb-roadmap-finding"

    Issue.create!(
      jira_key: "PG-78", epic: epics(:priority_two), summary: "Broadcast marker",
      jira_status: "In Progress", issue_type: "Task",
      created_at_jira: Time.current, status_changed_at_jira: Time.current
    )
    broadcast_board

    assert_selector "[data-tooltip-id='PG-78']", visible: :all
    assert_selector ".kb-roadmap-finding"
    assert_selector ".kb-roadmap-head[data-open='1']"
  end

  test "a closed roadmap line stays closed across a Turbo broadcast" do
    assert_no_selector ".kb-roadmap-finding"

    Issue.create!(
      jira_key: "PG-79", epic: epics(:priority_two), summary: "Broadcast marker",
      jira_status: "In Progress", issue_type: "Task",
      created_at_jira: Time.current, status_changed_at_jira: Time.current
    )
    broadcast_board

    assert_selector "[data-tooltip-id='PG-79']", visible: :all
    assert_no_selector ".kb-roadmap-finding"
  end
end
