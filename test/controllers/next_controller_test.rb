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

  test "renders the queue with each idea's blocker" do
    idea = DiscoveryIdea.create!(jira_key: "PGR-1", summary: "Windows builds",
                                 horizon: "next", incubator_status: "Prioritized")
    idea.idea_deliveries.create!(jira_key: "PG-2425", issue_type: "Story")

    get "/next"

    assert_response :success
    assert_select ".kb-next-summary", text: "Windows builds"
    assert_select ".kb-next-blocker", text: /Story/
  end

  test "says so when no roadmap is configured" do
    get "/next"
    assert_response :success
    assert_select ".kb-next-empty"
  end
end
