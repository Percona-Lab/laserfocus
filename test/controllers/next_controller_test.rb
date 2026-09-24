require "test_helper"

class NextControllerTest < ActionDispatch::IntegrationTest
  fixtures :epics, :issues

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    get "/auth/google_oauth2/callback"
  end

  test "requires login" do
    reset!
    get "/next"
    assert_redirected_to "/login"
  end

  test "renders a column per idea with its readiness steps as cards" do
    idea = DiscoveryIdea.create!(jira_key: "PGR-1", summary: "Windows builds",
                                 horizon: "next", incubator_status: "Prioritized")
    idea.idea_deliveries.create!(jira_key: "PG-2425", issue_type: "Story")

    get "/next"

    assert_response :success
    assert_select "#kb-next-PGR-1 .kb-col-name", text: "Windows builds"
    assert_select "#kb-next-PGR-1 .kb-col-count", text: "1/4"
    assert_select "#kb-next-PGR-1 .kb-step-card", count: 4
    assert_select "#kb-next-PGR-1 .kb-step-card[data-step='done']", text: /PG-2425/
    assert_select "#kb-next-PGR-1 .kb-step-card[data-step='current']", text: /Story/
  end

  test "shares the view tabs with the board" do
    get "/next"
    assert_select ".kb-view-tabs a", text: "Board"
    assert_select ".kb-view-tabs a", text: "Community"
    assert_select ".kb-view-tabs a[data-on='1']", text: "Next"
  end

  test "says so when no roadmap is configured" do
    get "/next"
    assert_response :success
    assert_select ".kb-next-empty"
  end
end
