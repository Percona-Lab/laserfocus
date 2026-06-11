require "test_helper"

class LaserFocus::ConfigTest < ActiveSupport::TestCase
  def fixture_yaml
    <<~YAML
      auth:
        allowed_domains: ["example.com"]
        allowed_emails: []
      polling:
        tick_seconds: 60
        active_window_minutes: 5
        idle_interval_minutes: 60
      board:
        epic_query: 'project = PG'
        users:
          - { jira_username: "alice", display_name: "Alice" }
        status_map:
          "To Do": "new"
          "Done":  "done"
        new_statuses:  ["new"]
        done_statuses: ["done"]
        staleness:
          somewhat_days: 7
          really_days:   21
        ignore_staleness_for_new_issues: true
    YAML
  end

  test "loads and exposes typed sections" do
    cfg = LaserFocus::Config.load_from_string(fixture_yaml)
    assert_equal [ "example.com" ], cfg.auth.allowed_domains
    assert_equal 60,              cfg.polling.tick_seconds
    assert_equal "new",           cfg.board.status_map.fetch("To Do")
    assert_equal 7,               cfg.board.staleness.somewhat_days
    assert_equal "alice",         cfg.board.users.first.jira_username
  end

  test "raises MissingKey when a required key is absent" do
    yaml = fixture_yaml.sub("epic_query: 'project = PG'", "")
    assert_raises(LaserFocus::Config::MissingKey) do
      LaserFocus::Config.load_from_string(yaml)
    end
  end

  test "resolves env-backed JIRA credentials" do
    previous = ENV["JIRA_API_TOKEN"]
    ENV["JIRA_API_TOKEN"] = "secret-token"
    cfg = LaserFocus::Config.load_from_string(fixture_yaml)
    assert_equal "secret-token", cfg.jira.api_token
  ensure
    ENV["JIRA_API_TOKEN"] = previous
  end
end
