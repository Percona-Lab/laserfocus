require "application_system_test_case"

class BoardEmptyLiveUpdateTest < ApplicationSystemTestCase
  FakeJiraIssue = Struct.new(:key, :fields, :attrs)

  setup do
    Issue.delete_all
    Epic.delete_all
    SyncRun.delete_all

    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "u1",
      info: { email: "alice@example.com", name: "Alice" }
    )
    visit "/auth/google_oauth2/callback"
    visit "/"
    assert_selector "main.kb-board#board-root"
    assert_no_selector ".kb-col"
  end

  test "first sync after page load on empty board shows new epic and issue without reload" do
    fake_client = Object.new
    epic_payload = FakeJiraIssue.new(
      "PG-1",
      { "summary" => "First Priority",
        "status" => { "name" => "In Progress" },
        "priority" => { "id" => "1" } },
      {}
    )
    child_payload = FakeJiraIssue.new(
      "PG-10",
      { "summary" => "Fresh task",
        "status" => { "name" => "In Progress" },
        "issuetype" => { "name" => "Task" },
        "parent" => { "key" => "PG-1" },
        "created" => 5.days.ago.iso8601 },
      { "changelog" => { "histories" => [] } }
    )
    fake_client.define_singleton_method(:search_all) do |jql, **_|
      case jql
      when /parent\s+in\s*\(\s*"?PG-1"?\s*\)/i then [ child_payload ]
      when /parent is EMPTY/i       then []
      when /labels.*Priority/i      then [ epic_payload ]
      else []
      end
    end

    JiraSync.singleton_class.send(:alias_method, :__orig_new, :new)
    JiraSync.singleton_class.send(:define_method, :new) { |**_| __orig_new(client: fake_client) }
    begin
      JiraSyncJob.new.perform
    ensure
      JiraSync.singleton_class.send(:remove_method, :new)
      JiraSync.singleton_class.send(:alias_method, :new, :__orig_new)
      JiraSync.singleton_class.send(:remove_method, :__orig_new)
    end

    assert_equal 1, Epic.count
    assert_selector %(.kb-col[data-epic-key="PG-1"])
    assert_selector %([data-tooltip-id="PG-10"])
  end
end
