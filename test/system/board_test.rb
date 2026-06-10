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
end
