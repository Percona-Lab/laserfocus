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

class LaserFocusConfigTest < ActiveSupport::TestCase
  BASE = <<~YAML
    auth: { allowed_domains: ["x.com"] }
    polling: { tick_seconds: 60, active_window_minutes: 5, idle_interval_minutes: 60 }
    board:
      epic_query: "project = PG"
      users: []
      status_map: { "To Do": "new" }
      new_statuses: ["new"]
      done_statuses: ["done"]
      staleness: { somewhat_days: 3, really_days: 10 }
  YAML

  test "reads closed_epics_query" do
    yaml = BASE + "  closed_epics_query: \"project = PG AND status = SUCCESS\"\n"
    cfg = LaserFocus::Config.load_from_string(yaml)
    assert_equal "project = PG AND status = SUCCESS", cfg.board.closed_epics_query
  end

  test "closed_epics_query is optional" do
    cfg = LaserFocus::Config.load_from_string(BASE)
    assert_nil cfg.board.closed_epics_query
  end

  test "reads new_unplanned_query" do
    yaml = BASE + "  new_unplanned_query: \"project = PG AND created >= -10d\"\n"
    cfg = LaserFocus::Config.load_from_string(yaml)
    assert_equal "project = PG AND created >= -10d", cfg.board.new_unplanned_query
  end

  test "new_unplanned_days defaults to 10" do
    cfg = LaserFocus::Config.load_from_string(BASE)
    assert_equal 10, cfg.board.new_unplanned_days
  end

  test "new_unplanned_days reads configured value" do
    yaml = BASE + "  new_unplanned_days: 5\n"
    cfg = LaserFocus::Config.load_from_string(yaml)
    assert_equal 5, cfg.board.new_unplanned_days
  end

  test "discovery is nil when the section is absent" do
    cfg = LaserFocus::Config.load_from_string(File.read(Rails.root.join("config/laserfocus.test.yml")))
    assert_nil cfg.discovery
  end

  test "discovery exposes its queries, fields and link type" do
    yaml = File.read(Rails.root.join("config/laserfocus.test.yml")) + <<~YAML
      discovery:
        now_query: 'project = PGR AND cf[11275] = "Now"'
        next_query: 'project = PGR AND cf[11275] = "Next"'
        horizon_field: "customfield_11275"
        incubator_field: "customfield_11290"
        rank_field: "customfield_10019"
    YAML
    d = LaserFocus::Config.load_from_string(yaml).discovery

    assert_equal %w[now next], d.queries.keys
    assert_equal "10016", d.delivery_link_type_id
    assert_equal %w[summary issuelinks customfield_11275 customfield_11290 customfield_10019], d.issue_fields
  end
end
