require "application_system_test_case"

class ViewTabsTest < ApplicationSystemTestCase
  fixtures :epics, :issues, :sync_runs

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    visit "/auth/google_oauth2/callback"
  end

  # Checked wide (one header row) and narrow (the header wraps), since the
  # views differ most in what would make the header wrap.
  test "the view tabs sit in the same spot on every view" do
    [ [ 1400, 900 ], [ 1100, 900 ] ].each do |size|
      page.driver.browser.manage.window.resize_to(*size)
      positions = %w[/ /community /next].map do |path|
        visit path
        assert_selector ".kb-view-tabs"
        page.evaluate_script("(r => [Math.round(r.left), Math.round(r.top)])(document.querySelector('.kb-view-tabs').getBoundingClientRect())")
      end

      assert_equal 1, positions.uniq.size, "tabs moved between views at #{size.first}px: #{positions.inspect}"
    end
  ensure
    page.driver.browser.manage.window.resize_to(1400, 900)
  end

  test "Next shows the ticket controls switched off" do
    visit "/next"
    assert_selector ".kb-search[disabled]"
    assert_selector ".kb-people-btn[disabled]"
    assert_no_selector ".kb-people-menu", visible: :all
  end
end
