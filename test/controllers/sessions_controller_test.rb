require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  test "callback signs in user with allowed domain" do
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    get "/auth/google_oauth2/callback"
    assert_redirected_to root_path
  end

  test "callback rejects unallowed domain" do
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "2",
      info: { email: "mallory@evil.com", name: "Mallory" }
    )
    get "/auth/google_oauth2/callback"
    assert_redirected_to "/login"
    follow_redirect!
    assert_select "body", /not authorized/i
  end

  test "logout clears session" do
    delete "/logout"
    assert_redirected_to "/login"
  end
end
