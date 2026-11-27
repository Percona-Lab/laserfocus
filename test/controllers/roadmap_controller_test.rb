require "test_helper"

class RoadmapControllerTest < ActionDispatch::IntegrationTest
  DISCOVERY = LaserFocus::Config::DiscoverySection.new(
    "roadmap_query" => "project = PGR AND issuetype = Idea",
    "time_id_field" => "customfield_11385",
    "horizon_field" => "customfield_11275",
    "codename_field" => "customfield_11386",
    "time_id_layout" => "QYY"
  )

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1", info: { email: "alice@example.com", name: "Alice" }
    )
    get "/auth/google_oauth2/callback"
    IdeaEvent.delete_all
    IdeaDelivery.delete_all
    DiscoveryIdea.delete_all
  end

  # Landing quarters for the duration of the block; the test config has none.
  def with_landing
    LASER_FOCUS_CONFIG.define_singleton_method(:discovery) { DISCOVERY }
    yield
  ensure
    LASER_FOCUS_CONFIG.singleton_class.send(:remove_method, :discovery)
  end

  test "requires login" do
    reset!
    get "/roadmap"
    assert_redirected_to "/login"
  end

  test "says so when landing quarters are switched off" do
    get "/roadmap"
    assert_response :success
    assert_select ".rm-empty", text: /switched off/
  end

  test "shows quarter cards, the timeline, the change log and the selected idea" do
    slipped = DiscoveryIdea.create!(jira_key: "PGR-17", summary: "TDE: Integration with AWS", horizon: "now", time_id: 127, codename: "Brave Bear")
    IdeaEvent.create!(jira_key: "PGR-17", field: "time_id", to_value: "426", occurred_at: Time.utc(2026, 10, 1), author: "Jan")
    IdeaEvent.create!(jira_key: "PGR-17", field: "time_id", from_value: "426", to_value: "127", occurred_at: Time.utc(2026, 11, 20), author: "Jan")
    DiscoveryIdea.create!(jira_key: "PGR-41", summary: "pgAdmin images", horizon: "now", codename: "Amber Ant")
    DiscoveryIdea.create!(jira_key: "PGR-8", summary: "OBS releases", horizon: "now", time_id: 426, codename: "Amber Ant")

    travel_to Time.utc(2026, 11, 27, 12) do
      with_landing { get "/roadmap", params: { idea: "PGR-17" } }
    end

    assert_response :success
    assert_select ".rm-card .rm-card-name", text: "Amber Ant"
    assert_select ".rm-card .rm-card-name", text: "Brave Bear"
    assert_select ".rm-item[data-sel='1'] .rm-tl-name", text: "TDE: Integration with AWS"
    assert_select ".rm-item .rm-ghost", count: 1
    assert_select ".rm-warn", text: /Time-ID not set/
    assert_select ".rm-item .lq-s-none", text: /Codename Ant/
    assert_select ".rm-feed-txt .d", text: /Slipped Q4 ’26 → Q1 ’27/
    assert_select "#rm-detail h3", text: "TDE: Integration with AWS"
  end
end
