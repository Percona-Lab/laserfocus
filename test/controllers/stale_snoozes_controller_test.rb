require "test_helper"
require "turbo/broadcastable/test_helper"

class StaleSnoozesControllerTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  fixtures :epics, :issues, :sync_runs

  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice Adams" }
    )
    get "/auth/google_oauth2/callback"
  end

  test "snoozes a ticket for the configured days in its current status" do
    freeze_time do
      patch "/stale_snooze", params: { key: "PG-11", reason: "  waiting on vendor  " }, as: :json
      assert_response :no_content

      snooze = StaleSnooze.find_by!(jira_key: "PG-11")
      assert_equal "In Review", snooze.jira_status
      assert_equal (LASER_FOCUS_CONFIG.board.snooze_days.days - LASER_FOCUS_CONFIG.board.staleness_lead).from_now, snooze.snoozed_until
      assert_equal "Alice Adams", snooze.snoozed_by
      assert_equal "waiting on vendor", snooze.reason
    end
  end

  test "snoozes a roadmap idea's landing warnings in their current state" do
    discovery = LaserFocus::Config::DiscoverySection.new(
      "roadmap_query" => "project = PGR", "time_id_field" => "customfield_1", "time_id_layout" => "QYY"
    )
    DiscoveryIdea.create!(jira_key: "PGR-41", summary: "pgAdmin images", horizon: "now", codename: "Amber Ant")
    LASER_FOCUS_CONFIG.define_singleton_method(:discovery) { discovery }

    patch "/stale_snooze", params: { key: "PGR-41", reason: "Time-ID comes with planning" }, as: :json

    assert_response :no_content
    snooze = StaleSnooze.find_by!(jira_key: "PGR-41")
    assert_equal "landing:no_time_id:", snooze.jira_status
    assert_equal "Time-ID comes with planning", snooze.reason
  ensure
    LASER_FOCUS_CONFIG.singleton_class.send(:remove_method, :discovery) if LASER_FOCUS_CONFIG.singleton_methods.include?(:discovery)
  end

  test "a blank reason is stored as none" do
    patch "/stale_snooze", params: { key: "PG-11", reason: "   " }, as: :json
    assert_nil StaleSnooze.find_by!(jira_key: "PG-11").reason
  end

  test "an overlong reason is cut to the limit" do
    patch "/stale_snooze", params: { key: "PG-11", reason: "x" * 500 }, as: :json
    assert_equal StaleSnooze::REASON_LIMIT, StaleSnooze.find_by!(jira_key: "PG-11").reason.length
  end

  test "snoozing again renews the one snooze" do
    StaleSnooze.create!(jira_key: "PG-11", jira_status: "In Progress", snoozed_until: 1.day.from_now,
                        snoozed_by: "Bob", reason: "old")
    patch "/stale_snooze", params: { key: "PG-11" }, as: :json

    assert_equal 1, StaleSnooze.count
    snooze = StaleSnooze.first
    assert_equal "In Review", snooze.jira_status
    assert_equal "Alice Adams", snooze.snoozed_by
    assert_nil snooze.reason
    assert_operator snooze.snoozed_until, :>, 6.days.from_now
  end

  test "falls back to the email when the session has no name" do
    OmniAuth.config.mock_auth[:google_oauth2].info.name = nil
    get "/auth/google_oauth2/callback"
    patch "/stale_snooze", params: { key: "PG-11" }, as: :json
    assert_equal "alice@example.com", StaleSnooze.find_by!(jira_key: "PG-11").snoozed_by
  end

  test "unknown and removed tickets are not found and nothing is broadcast" do
    Issue.find_by!(jira_key: "PG-10").update!(removed_at: Time.current)
    assert_no_turbo_stream_broadcasts("board") do
      patch "/stale_snooze", params: { key: "PG-404" }, as: :json
      assert_response :not_found
      patch "/stale_snooze", params: { key: "PG-10" }, as: :json
      assert_response :not_found
    end
    assert_equal 0, StaleSnooze.count
  end

  test "broadcasts the board after snoozing, and leaves the Reviews view alone" do
    assert_no_turbo_stream_broadcasts("reviews") do
      assert_turbo_stream_broadcasts("board") do
        patch "/stale_snooze", params: { key: "PG-11" }, as: :json
      end
    end
  end

  test "unsnoozes and broadcasts" do
    StaleSnooze.create!(jira_key: "PG-11", jira_status: "In Review", snoozed_until: 1.day.from_now, snoozed_by: "Bob")
    assert_turbo_stream_broadcasts("board") do
      delete "/stale_snooze", params: { key: "PG-11" }, as: :json
      assert_response :no_content
    end
    assert_equal 0, StaleSnooze.count
  end

  test "unsnoozing something not snoozed does not broadcast" do
    assert_no_turbo_stream_broadcasts("board") do
      delete "/stale_snooze", params: { key: "PG-11" }, as: :json
      assert_response :no_content
    end
  end

  test "requires login" do
    reset!
    patch "/stale_snooze", params: { key: "PG-11" }, as: :json
    assert_redirected_to "/login"
    delete "/stale_snooze", params: { key: "PG-11" }, as: :json
    assert_redirected_to "/login"
    assert_equal 0, StaleSnooze.count
  end

  test "snoozes a PR on the Reviews view for the state the ball is in" do
    pr = ReviewPullRequest.create!(repo: "acme/server", number: 9, title: "Fix", url: "https://github.com/acme/server/pull/9",
                                   author: "bob-gh", opened_at: 10.days.ago, stage: "needs", waiting_on: "reviewers",
                                   waiting_since: 10.days.ago)
    assert_turbo_stream_broadcasts("reviews") do
      patch "/stale_snooze", params: { key: "acme/server#9", reason: "waiting on upstream" }, as: :json
    end
    assert_response :no_content

    snooze = StaleSnooze.find_by!(jira_key: "acme/server#9")
    assert_equal pr.snooze_state, snooze.jira_status
    assert_equal "waiting on upstream", snooze.reason
  end

  test "an unknown PR key is not found" do
    patch "/stale_snooze", params: { key: "acme/server#404" }, as: :json
    assert_response :not_found
  end

  test "snoozes an issue on the Issues view and refreshes that view" do
    issue = GithubIssue.create!(repo: "acme/server", number: 12, title: "Crash", url: "https://github.com/acme/server/issues/12",
                                author: "rita", opened_at: 10.days.ago, stage: "new", waiting_on: "team", waiting_since: 10.days.ago)
    assert_no_turbo_stream_broadcasts("reviews") do
      assert_turbo_stream_broadcasts("issues") do
        patch "/stale_snooze", params: { key: "acme/server#12" }, as: :json
      end
    end
    assert_equal issue.snooze_state, StaleSnooze.find_by!(jira_key: "acme/server#12").jira_status
  end
end
