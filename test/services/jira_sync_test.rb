require "test_helper"
require "webmock/minitest"

class JiraSyncTest < ActiveSupport::TestCase
  setup do
    WebMock.disable_net_connect!
    Issue.delete_all
    Epic.delete_all
    BoardOrder.delete_all
    stub_request(:get, %r{/dev-status}).to_return(
      status: 200,
      body: '{"errors":[],"configErrors":[],"summary":{"pullrequest":{"overall":{"count":0},"byInstanceType":{}}},"detail":[]}',
      headers: { "Content-Type" => "application/json" }
    )
  end

  test "upserts epics and their children" do
    # Permissive stubs; jira-ruby's exact URL format is internal.
    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = case decoded
      when /labels.*Priority/i
               { "issues" => [
                   { "key" => "PG-1", "fields" => { "summary" => "Epic A",
                                                    "status" => { "name" => "In Progress" },
                                                    "priority" => { "id" => "1" } } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      when /parent\s+in\s*\(.*PG-1.*\)/i
               { "issues" => [
                   { "key" => "PG-10", "fields" => { "summary" => "Child A",
                                                     "status" => { "name" => "To Do" },
                                                     "issuetype" => { "name" => "Task" },
                                                     "assignee" => { "name" => "alice" },
                                                     "parent" => { "key" => "PG-1" },
                                                     "labels" => [ "backend", "priority" ],
                                                     "components" => [ { "name" => "API" } ] } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json,
        headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(epic_query: 'project = PG AND labels = "Priority"').run!

    assert_equal 1, Epic.count
    assert_equal "Epic A", Epic.first.name
    assert_equal 1, Issue.count
    assert_equal "PG-10", Issue.first.jira_key
    assert_equal [ "backend", "priority" ], Issue.first.labels
    assert_equal [ "API" ], Issue.first.components
  end

  test "fetches subtasks below epic children" do
    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = case decoded
      when /parent\s+in\s*\([^)]*PG-10[^)]*\)/i
               { "issues" => [
                   { "key" => "PG-11", "fields" => { "summary" => "Subtask A",
                                                     "status" => { "name" => "In Progress" },
                                                     "issuetype" => { "name" => "Sub-task" },
                                                     "parent" => { "key" => "PG-10" } } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      when /labels.*Priority/i
               { "issues" => [
                   { "key" => "PG-1", "fields" => { "summary" => "Epic A",
                                                    "status" => { "name" => "In Progress" },
                                                    "priority" => { "id" => "1" } } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      when /parent\s+in\s*\([^)]*PG-1[^)]*\)/i
               { "issues" => [
                   { "key" => "PG-10", "fields" => { "summary" => "Story A",
                                                     "status" => { "name" => "In Progress" },
                                                     "issuetype" => { "name" => "Story" },
                                                     "parent" => { "key" => "PG-1" } } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json,
        headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(epic_query: 'project = PG AND labels = "Priority"').run!

    story = Issue.find_by!(jira_key: "PG-10")
    subtask = Issue.find_by!(jira_key: "PG-11")
    assert_equal story.epic_id, subtask.epic_id
    assert_equal "PG-10", subtask.parent_jira_key
  end

  test "uses last status change from changelog for status_changed_at_jira" do
    changed_at = "2026-06-03T10:00:00.000+0000"
    created_at = "2026-05-01T09:00:00.000+0000"

    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = case decoded
      when /labels.*Priority/i
               { "issues" => [
                   { "key" => "PG-1", "fields" => { "summary" => "Epic A",
                                                    "status" => { "name" => "In Progress" },
                                                    "priority" => { "id" => "1" } } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      when /parent\s+in\s*\(.*PG-1.*\)/i
               { "issues" => [
                   { "key" => "PG-10",
                     "fields" => { "summary" => "Child A",
                                   "status" => { "name" => "In Progress" },
                                   "issuetype" => { "name" => "Task" },
                                   "created" => created_at,
                                   "parent" => { "key" => "PG-1" } },
                     "changelog" => { "histories" => [
                       { "created" => "2026-05-02T09:00:00.000+0000",
                         "items" => [ { "field" => "assignee", "toString" => "alice" } ] },
                       { "created" => changed_at,
                         "items" => [ { "field" => "status", "fromString" => "To Do",
                                       "toString" => "In Progress" } ] }
                     ] } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json,
        headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(epic_query: 'project = PG AND labels = "Priority"').run!

    issue = Issue.find_by!(jira_key: "PG-10")
    assert_equal Time.parse(changed_at), issue.status_changed_at_jira
  end

  test "leaves status_changed_at_jira nil when changelog has no status change" do
    created_at = "2026-05-01T09:00:00.000+0000"

    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = case decoded
      when /labels.*Priority/i
               { "issues" => [
                   { "key" => "PG-1", "fields" => { "summary" => "Epic A",
                                                    "status" => { "name" => "To Do" },
                                                    "priority" => { "id" => "1" } } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      when /parent\s+in\s*\(.*PG-1.*\)/i
               { "issues" => [
                   { "key" => "PG-11",
                     "fields" => { "summary" => "Child B",
                                   "status" => { "name" => "To Do" },
                                   "issuetype" => { "name" => "Task" },
                                   "created" => created_at,
                                   "parent" => { "key" => "PG-1" } },
                     "changelog" => { "histories" => [] } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json,
        headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(epic_query: 'project = PG AND labels = "Priority"').run!

    issue = Issue.find_by!(jira_key: "PG-11")
    assert_nil issue.status_changed_at_jira
    assert_equal Time.parse(created_at), issue.created_at_jira
  end

  test "upserts orphan issues from unplanned_query with nil epic" do
    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = case decoded
      when /parent is EMPTY/i
               { "issues" => [
                   { "key" => "PG-77",
                     "fields" => { "summary" => "Loose ticket",
                                   "status" => { "name" => "In Progress" },
                                   "issuetype" => { "name" => "Task" } } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json,
        headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(
      epic_query: "project = PG",
      unplanned_query: "project = PG AND parent is EMPTY"
    ).run!

    orphan = Issue.find_by!(jira_key: "PG-77")
    assert_nil orphan.epic_id
    assert_equal 1, Issue.orphan.active.count
  end

  test "marks previously-seen orphans as removed when they fall out of the query" do
    stale = Issue.create!(
      jira_key: "PG-66", epic: nil, issue_type: "Task",
      summary: "Gone", jira_status: "Done"
    )

    stub_request(:get, %r{/search}).to_return(
      status: 200,
      body: { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    JiraSync.new(
      epic_query: "project = PG",
      unplanned_query: "project = PG AND parent is EMPTY"
    ).run!

    assert_not_nil stale.reload.removed_at
  end

  test "does not create orphan Issue when the same key is already an epic" do
    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = case decoded
      when /labels.*Priority/i
               { "issues" => [
                   { "key" => "PG-5", "fields" => { "summary" => "Priority issue without parent",
                                                    "status" => { "name" => "In Progress" },
                                                    "priority" => { "id" => "2" } } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 100 }
      when /parent is EMPTY/i
               { "issues" => [
                   { "key" => "PG-5", "fields" => { "summary" => "Priority issue without parent",
                                                    "status" => { "name" => "In Progress" },
                                                    "issuetype" => { "name" => "Story" } } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 100 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 100 }
      end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(
      epic_query: 'project = PG AND labels = "Priority"',
      unplanned_query: "project = PG AND parent is EMPTY"
    ).run!

    assert_equal 0, Epic.active.count, "PG-5 must not appear as a column"
    assert_equal 1, Issue.active.orphan.count
    assert_equal "PG-5", Issue.active.orphan.first.jira_key
  end

  test "skips unplanned fetch when unplanned_query is blank" do
    stub_request(:get, %r{/search}).to_return(
      status: 200,
      body: { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    JiraSync.new(epic_query: "project = PG", unplanned_query: nil, new_unplanned_query: nil).run!

    assert_requested(:get, %r{/search}, times: 1)
  end

  test "records a SyncRun on success" do
    stub_request(:get, %r{/search}).to_return(
      status: 200,
      body: { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    assert_difference -> { SyncRun.ok.count }, 1 do
      JiraSync.new(epic_query: "project = PG").run!
    end
  end

  test "marks SyncRun as failed when JIRA errors" do
    stub_request(:get, %r{/search}).to_return(status: 500, body: "boom")

    assert_difference -> { SyncRun.count }, 1 do
      assert_nothing_raised { JiraSync.new(epic_query: "project = PG").run! }
    end
    assert_not SyncRun.most_recent.first.ok
  end

  test "records an EpicEvent when a new epic first appears" do
    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = case decoded
      when /labels.*Priority/i
               { "issues" => [
                   { "key" => "PG-1", "fields" => { "summary" => "Epic A",
                                                    "status" => { "name" => "In Progress" },
                                                    "priority" => { "id" => "1" } } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    assert_difference -> { EpicEvent.count }, 1 do
      JiraSync.new(epic_query: 'project = PG AND labels = "Priority"', unplanned_query: nil).run!
    end

    event = EpicEvent.last
    assert_equal "added", event.event_type
    assert_equal "PG-1", event.jira_key
    assert_equal "Epic A", event.name

    # A second sync with the epic still present must not record another event.
    assert_no_difference -> { EpicEvent.count } do
      JiraSync.new(epic_query: 'project = PG AND labels = "Priority"', unplanned_query: nil).run!
    end
  end

  test "records an EpicEvent when an epic drops out of the query" do
    epic = Epic.create!(jira_key: "PG-9", name: "Gone soon", priority: 1, jira_status: "In Progress")

    stub_request(:get, %r{/search}).to_return(
      status: 200,
      body: { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    assert_difference -> { EpicEvent.count }, 1 do
      JiraSync.new(epic_query: 'project = PG AND labels = "Priority"').run!
    end

    event = EpicEvent.last
    assert_equal "removed", event.event_type
    assert_equal epic.jira_key, event.jira_key
    assert_not_nil epic.reload.removed_at
  end

  test "backdates the added event to when the Priority label actually landed" do
    labeled_at = "2026-06-01T08:00:00.000+0000"

    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = case decoded
      when /labels.*Priority/i
               { "issues" => [
                   { "key" => "PG-1", "fields" => { "summary" => "Epic A",
                                                    "status" => { "name" => "In Progress" },
                                                    "priority" => { "id" => "1" } },
                     "changelog" => { "histories" => [
                       { "created" => "2026-05-20T09:00:00.000+0000",
                         "items" => [ { "field" => "labels", "toString" => "backend",
                                       "fromString" => "" } ] },
                       { "created" => labeled_at,
                         "items" => [ { "field" => "labels", "toString" => "backend Priority",
                                       "fromString" => "backend" } ] }
                     ] } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(epic_query: 'project = PG AND labels = "Priority"', unplanned_query: nil).run!

    event = EpicEvent.last
    assert_equal "added", event.event_type
    assert_equal Time.parse(labeled_at), event.occurred_at
  end

  test "added event prefers the Priority label add over a later unrelated status change" do
    labeled_at = "2026-06-01T08:00:00.000+0000"
    status_changed_at = "2026-06-20T10:00:00.000+0000"

    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = case decoded
      when /labels.*Priority/i
               { "issues" => [
                   { "key" => "PG-1", "fields" => { "summary" => "Epic A",
                                                    "status" => { "name" => "In Progress" },
                                                    "priority" => { "id" => "1" } },
                     "changelog" => { "histories" => [
                       { "created" => labeled_at,
                         "items" => [ { "field" => "labels", "toString" => "Priority",
                                       "fromString" => "" } ] },
                       { "created" => status_changed_at,
                         "items" => [ { "field" => "status", "fromString" => "To Do",
                                       "toString" => "In Progress" } ] }
                     ] } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(epic_query: 'project = PG AND labels = "Priority"', unplanned_query: nil).run!

    event = EpicEvent.last
    assert_equal "added", event.event_type
    assert_equal Time.parse(labeled_at), event.occurred_at
  end

  test "re-add is never backdated before the epic's previous removed event" do
    stale_label_add = "2026-05-01T08:00:00.000+0000"
    epic = Epic.create!(jira_key: "PG-1", name: "Epic A", priority: 1, jira_status: "In Progress",
                        removed_at: Time.current)
    EpicEvent.create!(epic: epic, jira_key: "PG-1", name: "Epic A", event_type: "removed",
                      occurred_at: Time.parse("2026-06-10T12:00:00.000+0000"))

    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = case decoded
      when /labels.*Priority/i
               { "issues" => [
                   { "key" => "PG-1", "fields" => { "summary" => "Epic A",
                                                    "status" => { "name" => "In Progress" },
                                                    "priority" => { "id" => "1" } },
                     "changelog" => { "histories" => [
                       { "created" => stale_label_add,
                         "items" => [ { "field" => "labels", "toString" => "Priority",
                                       "fromString" => "" } ] }
                     ] } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(epic_query: 'project = PG AND labels = "Priority"', unplanned_query: nil).run!

    event = EpicEvent.where(jira_key: "PG-1", event_type: "added").last
    assert_operator event.occurred_at, :>, Time.parse("2026-06-10T12:00:00.000+0000")
  end

  test "backdates the removed event to when the epic dropped out via a follow-up changelog lookup" do
    epic = Epic.create!(jira_key: "PG-9", name: "Gone soon", priority: 1, jira_status: "In Progress")
    dropped_at = "2026-06-15T14:30:00.000+0000"

    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = if decoded =~ /key\s+in\s*\(.*PG-9.*\)/i
               { "issues" => [
                   { "key" => "PG-9", "fields" => { "summary" => "Gone soon" },
                     "changelog" => { "histories" => [
                       { "created" => dropped_at,
                         "items" => [ { "field" => "status", "fromString" => "In Progress",
                                       "toString" => "SUCCESS" } ] }
                     ] } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(epic_query: 'project = PG AND labels = "Priority"').run!

    event = EpicEvent.last
    assert_equal "removed", event.event_type
    assert_equal epic.jira_key, event.jira_key
    assert_equal Time.parse(dropped_at), event.occurred_at
  end

  test "backfill_event_times! corrects a stale bootstrap timestamp from the changelog" do
    real_time = "2026-05-10T11:00:00.000+0000"
    event = EpicEvent.create!(jira_key: "PG-20", name: "Backfill me", event_type: "added",
                              occurred_at: Time.current)

    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = if decoded =~ /key\s+in\s*\(.*PG-20.*\)/i
               { "issues" => [
                   { "key" => "PG-20", "fields" => { "summary" => "Backfill me" },
                     "changelog" => { "histories" => [
                       { "created" => real_time,
                         "items" => [ { "field" => "labels", "toString" => "Priority",
                                       "fromString" => "" } ] }
                     ] } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    updated = JiraSync.new.backfill_event_times!

    assert_equal 1, updated
    assert_equal Time.parse(real_time), event.reload.occurred_at
  end

  test "backfill_event_times! skips a jira_key with more than one event" do
    EpicEvent.create!(jira_key: "PG-21", name: "Ambiguous", event_type: "added", occurred_at: 2.days.ago)
    EpicEvent.create!(jira_key: "PG-21", name: "Ambiguous", event_type: "removed", occurred_at: 1.day.ago)

    stub_request(:get, %r{/search}).to_return(
      status: 200,
      body: { "issues" => [
          { "key" => "PG-21", "fields" => { "summary" => "Ambiguous" },
            "changelog" => { "histories" => [
              { "created" => "2026-05-10T11:00:00.000+0000",
                "items" => [ { "field" => "status", "fromString" => "In Progress", "toString" => "SUCCESS" } ] }
            ] } }
        ], "total" => 1, "startAt" => 0, "maxResults" => 50 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    assert_equal 0, JiraSync.new.backfill_event_times!
  end

  test "backfill_event_times! leaves rows untouched when the changelog lookup fails" do
    original_time = Time.parse("2026-06-01T08:00:00.000+0000")
    event = EpicEvent.create!(jira_key: "PG-23", name: "Unlucky", event_type: "added",
                              occurred_at: original_time)

    stub_request(:get, %r{/search}).to_return(
      status: 400,
      body: { "errorMessages" => [ "An issue with key 'PG-23' does not exist" ] }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    assert_nothing_raised do
      assert_equal 0, JiraSync.new.backfill_event_times!
    end
    assert_equal original_time, event.reload.occurred_at
  end

  test "backfill_event_times! makes no request when there are no events" do
    assert_equal 0, JiraSync.new.backfill_event_times!
    assert_not_requested(:get, %r{/search})
  end

  test "discover_closed_epics! backfills add+remove history for an epic closed before tracking began" do
    labeled_at = "2026-04-01T09:00:00.000+0000"
    closed_at = "2026-04-20T16:00:00.000+0000"

    stub_request(:get, %r{/search}).to_return(
      status: 200,
      body: { "issues" => [
          { "key" => "PG-2502", "fields" => { "summary" => "Old finished epic",
                                              "status" => { "name" => "SUCCESS" },
                                              "created" => "2026-03-01T09:00:00.000+0000" },
            "changelog" => { "histories" => [
              { "created" => labeled_at,
                "items" => [ { "field" => "labels", "toString" => "Priority", "fromString" => "" } ] },
              { "created" => closed_at,
                "items" => [ { "field" => "status", "fromString" => "In Progress", "toString" => "SUCCESS" } ] }
            ] } }
        ], "total" => 1, "startAt" => 0, "maxResults" => 50 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    created = JiraSync.new.discover_closed_epics!('status IN (SUCCESS, FAILURE, REJECTED, "GONE BAD")')

    assert_equal 1, created
    epic = Epic.find_by!(jira_key: "PG-2502")
    assert_not_nil epic.removed_at

    added = EpicEvent.find_by!(jira_key: "PG-2502", event_type: "added")
    removed = EpicEvent.find_by!(jira_key: "PG-2502", event_type: "removed")
    assert_equal Time.parse(labeled_at), added.occurred_at
    assert_equal Time.parse(closed_at), removed.occurred_at
  end

  test "discover_closed_epics! falls back to the epic's own created date when labels history is missing" do
    created_at = "2026-03-01T09:00:00.000+0000"
    closed_at = "2026-04-20T16:00:00.000+0000"

    stub_request(:get, %r{/search}).to_return(
      status: 200,
      body: { "issues" => [
          { "key" => "PG-2503", "fields" => { "summary" => "Created already labeled",
                                              "status" => { "name" => "FAILURE" },
                                              "created" => created_at },
            "changelog" => { "histories" => [
              { "created" => closed_at,
                "items" => [ { "field" => "status", "fromString" => "In Progress", "toString" => "FAILURE" } ] }
            ] } }
        ], "total" => 1, "startAt" => 0, "maxResults" => 50 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    JiraSync.new.discover_closed_epics!('status IN (SUCCESS, FAILURE, REJECTED, "GONE BAD")')

    added = EpicEvent.find_by!(jira_key: "PG-2503", event_type: "added")
    assert_equal Time.parse(created_at), added.occurred_at
  end

  test "discover_closed_epics! skips a key that's already tracked" do
    Epic.create!(jira_key: "PG-2504", name: "Already known", priority: 1, jira_status: "SUCCESS",
                removed_at: Time.current)

    stub_request(:get, %r{/search}).to_return(
      status: 200,
      body: { "issues" => [
          { "key" => "PG-2504", "fields" => { "summary" => "Already known", "status" => { "name" => "SUCCESS" } } }
        ], "total" => 1, "startAt" => 0, "maxResults" => 50 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    assert_no_difference -> { EpicEvent.count } do
      assert_equal 0, JiraSync.new.discover_closed_epics!('status IN (SUCCESS, FAILURE, REJECTED, "GONE BAD")')
    end
  end

  def jira_time(t) = t.strftime("%Y-%m-%dT%H:%M:%S.000%z")

  test "upserts a fresh new-status candidate as provisional orphan" do
    created = jira_time(2.days.ago)
    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = if decoded =~ /statusCategory\s*=\s*"To Do"/i
               { "issues" => [
                   { "key" => "PG-500", "fields" => {
                       "summary" => "Brand new", "status" => { "name" => "To Do" },
                       "issuetype" => { "name" => "Task" }, "created" => created } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(
      epic_query: "project = PG", unplanned_query: nil,
      new_unplanned_query: 'project = PG AND statusCategory = "To Do"',
      new_unplanned_days: 10,
      status_map: { "To Do" => "new" }, new_statuses: [ "new" ]
    ).run!

    issue = Issue.find_by!(jira_key: "PG-500")
    assert_nil issue.epic_id
    assert_equal true, issue.provisional
  end

  test "candidate also returned by unplanned_query stays non-provisional" do
    created = jira_time(2.days.ago)
    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      fields = { "summary" => "Dual", "status" => { "name" => "To Do" },
                 "issuetype" => { "name" => "Task" }, "created" => created }
      body = if decoded =~ /parent is EMPTY/i
               { "issues" => [ { "key" => "PG-501", "fields" => fields } ],
                 "total" => 1, "startAt" => 0, "maxResults" => 50 }
      elsif decoded =~ /statusCategory\s*=\s*"To Do"/i
               { "issues" => [ { "key" => "PG-501", "fields" => fields } ],
                 "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(
      epic_query: "project = PG",
      unplanned_query: "project = PG AND parent is EMPTY",
      new_unplanned_query: 'project = PG AND statusCategory = "To Do"',
      new_unplanned_days: 10,
      status_map: { "To Do" => "new" }, new_statuses: [ "new" ]
    ).run!

    assert_equal false, Issue.find_by!(jira_key: "PG-501").provisional
  end

  test "ignores candidates older than the window" do
    created = jira_time(40.days.ago)
    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = if decoded =~ /statusCategory\s*=\s*"To Do"/i
               { "issues" => [
                   { "key" => "PG-502", "fields" => {
                       "summary" => "Old", "status" => { "name" => "To Do" },
                       "issuetype" => { "name" => "Task" }, "created" => created } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(
      epic_query: "project = PG", unplanned_query: nil,
      new_unplanned_query: 'project = PG AND statusCategory = "To Do"',
      new_unplanned_days: 10,
      status_map: { "To Do" => "new" }, new_statuses: [ "new" ]
    ).run!

    assert_nil Issue.find_by(jira_key: "PG-502")
  end

  test "ignores candidates whose mapped status is not new" do
    created = jira_time(2.days.ago)
    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      body = if decoded =~ /statusCategory\s*=\s*"To Do"/i
               { "issues" => [
                   { "key" => "PG-503", "fields" => {
                       "summary" => "InProg", "status" => { "name" => "In Progress" },
                       "issuetype" => { "name" => "Task" }, "created" => created } }
                 ], "total" => 1, "startAt" => 0, "maxResults" => 50 }
      else
               { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }
      end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    JiraSync.new(
      epic_query: "project = PG", unplanned_query: nil,
      new_unplanned_query: 'project = PG AND statusCategory = "To Do"',
      new_unplanned_days: 10,
      status_map: { "To Do" => "new", "In Progress" => "in_progress" },
      new_statuses: [ "new" ]
    ).run!

    assert_nil Issue.find_by(jira_key: "PG-503")
  end

  test "prunes a provisional issue that is no longer returned" do
    stale = Issue.create!(jira_key: "PG-504", epic: nil, issue_type: "Task",
                          summary: "Was new", jira_status: "To Do", provisional: true)
    stub_request(:get, %r{/search}).to_return(
      status: 200,
      body: { "issues" => [], "total" => 0, "startAt" => 0, "maxResults" => 50 }.to_json,
      headers: { "Content-Type" => "application/json" }
    )

    JiraSync.new(
      epic_query: "project = PG", unplanned_query: nil,
      new_unplanned_query: 'project = PG AND statusCategory = "To Do"',
      status_map: { "To Do" => "new" }, new_statuses: [ "new" ]
    ).run!

    assert_not_nil stale.reload.removed_at
  end
end
