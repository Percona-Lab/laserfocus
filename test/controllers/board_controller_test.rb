require "test_helper"

class BoardControllerTest < ActionDispatch::IntegrationTest
  fixtures :epics, :issues

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    get "/auth/google_oauth2/callback"
  end

  test "renders columns for active epics" do
    get root_path
    assert_response :success
    assert_select ".kb-col", count: 2
  end

  test "redirects to login when unauthenticated" do
    reset!
    get root_path
    assert_redirected_to "/login"
  end

  test "renders a card per active issue" do
    get root_path
    assert_select ".kb-card"
  end
end
