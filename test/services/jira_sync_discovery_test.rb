require "test_helper"
require "webmock/minitest"

class JiraSyncDiscoveryTest < ActiveSupport::TestCase
  DISCOVERY = LaserFocus::Config::DiscoverySection.new(
    "now_query"  => 'project = PGR AND cf[11275] = "Now"',
    "next_query" => 'project = PGR AND cf[11275] = "Next"',
    "delivery_link_type_id" => "10016",
    "horizon_field"   => "customfield_11275",
    "incubator_field" => "customfield_11290",
    "rank_field"      => "customfield_10019"
  )

  setup do
    WebMock.disable_net_connect!
    IdeaDelivery.delete_all
    DiscoveryIdea.delete_all
    Issue.delete_all
    Epic.delete_all
    BoardOrder.delete_all
    stub_request(:get, %r{/dev-status}).to_return(
      status: 200,
      body: '{"errors":[],"configErrors":[],"summary":{"pullrequest":{"overall":{"count":0},"byInstanceType":{}}},"detail":[]}',
      headers: { "Content-Type" => "application/json" }
    )
  end

  def idea(key, summary:, incubator: "Committed", rank: "0|a", delivery: nil, link_type: "10016")
    links = if delivery
      [ { "type" => { "id" => link_type, "name" => "Polaris work item link" },
          "inwardIssue" => { "key" => delivery[:key],
                             "fields" => { "issuetype" => { "name" => delivery[:type] } } } } ]
    else
      []
    end
    { "key" => key, "fields" => {
        "summary" => summary,
        "status" => { "name" => "Ideation" },
        "customfield_11290" => { "value" => incubator },
        "customfield_10019" => rank,
        "issuelinks" => links
      } }
  end

  def page(issues)
    { "issues" => issues, "total" => issues.size, "startAt" => 0, "maxResults" => 50 }
  end

  def stub_search(&block)
    stub_request(:get, %r{/search}).to_return do |req|
      body = block.call(CGI.unescape(req.uri.to_s)) || page([])
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end
  end

  def run_sync(epic_query: 'project = PG AND labels = "Priority"')
    JiraSync.new(epic_query: epic_query, unplanned_query: nil,
                 new_unplanned_query: nil, discovery: DISCOVERY).run!
  end

  test "stores ideas, their horizon and their delivery links" do
    stub_search do |q|
      if q.include?('"Now"')
        page([ idea("PGR-43", summary: "pgBackRest KMS support",
                    delivery: { key: "PG-2774", type: "Epic" }) ])
      elsif q.include?('"Next"')
        page([ idea("PGR-9", summary: "TDE: KMS unavailability", incubator: "Prioritized",
                    delivery: { key: "PG-1572", type: "Epic" }) ])
      end
    end

    run_sync

    assert_equal %w[PGR-43], DiscoveryIdea.now.pluck(:jira_key)
    assert_equal %w[PGR-9], DiscoveryIdea.next_up.pluck(:jira_key)

    now_idea = DiscoveryIdea.find_by(jira_key: "PGR-43")
    assert_equal "pgBackRest KMS support", now_idea.summary
    assert_equal "Committed", now_idea.incubator_status
    assert_equal %w[PG-2774], now_idea.delivery_keys
    assert_equal "Epic", now_idea.idea_deliveries.first.issue_type
  end

  test "ignores issue links that are not delivery links" do
    stub_search do |q|
      page([ idea("PGR-43", summary: "Idea", delivery: { key: "PG-1", type: "Epic" },
                  link_type: "10003") ]) if q.include?('"Now"')
    end

    run_sync

    assert_equal [], DiscoveryIdea.find_by(jira_key: "PGR-43").delivery_keys
  end

  test "keeps a delivery target that is a Story, not an Epic" do
    stub_search do |q|
      page([ idea("PGR-42", summary: "QA automation",
                  delivery: { key: "PG-2425", type: "Story" }) ]) if q.include?('"Now"')
    end

    run_sync

    assert_equal "Story", IdeaDelivery.find_by(jira_key: "PG-2425").issue_type
  end

  test "an epic behind a Now idea joins the board without the Priority label" do
    stub_search do |q|
      if q.include?('"Now"')
        page([ idea("PGR-41", summary: "pgAdmin builds", delivery: { key: "PG-2739", type: "Epic" }) ])
      elsif q =~ /labels.*Priority/i
        page([ { "key" => "PG-1", "fields" => { "summary" => "Labelled epic",
                                                "status" => { "name" => "In Progress" },
                                                "priority" => { "id" => "1" } } } ])
      elsif q =~ /key in \(.*PG-2739.*\)/i
        page([ { "key" => "PG-2739", "fields" => { "summary" => "pgAdmin builds",
                                                   "status" => { "name" => "To Do" },
                                                   "priority" => { "id" => "3" } } } ])
      end
    end

    run_sync

    assert_equal %w[PG-1 PG-2739].sort, Epic.active.pluck(:jira_key).sort
  end

  test "an idea dropping out of both queries is marked removed" do
    stub_search { |q| page([ idea("PGR-43", summary: "Idea") ]) if q.include?('"Now"') }
    run_sync
    assert_equal 1, DiscoveryIdea.active.count

    stub_search { |_q| page([]) }
    run_sync
    assert_equal 0, DiscoveryIdea.active.count
    assert_equal 1, DiscoveryIdea.count
  end

  test "a delivery link removed in Jira is dropped locally" do
    stub_search do |q|
      page([ idea("PGR-43", summary: "Idea", delivery: { key: "PG-1", type: "Epic" }) ]) if q.include?('"Now"')
    end
    run_sync
    assert_equal %w[PG-1], DiscoveryIdea.find_by(jira_key: "PGR-43").delivery_keys

    stub_search { |q| page([ idea("PGR-43", summary: "Idea") ]) if q.include?('"Now"') }
    run_sync
    assert_equal [], DiscoveryIdea.find_by(jira_key: "PGR-43").reload.delivery_keys
  end

  test "a failing discovery query leaves the board sync alone" do
    stub_request(:get, %r{/search}).to_return do |req|
      decoded = CGI.unescape(req.uri.to_s)
      if decoded.include?("PGR")
        { status: 400, body: '{"errorMessages":["Field does not exist"]}',
          headers: { "Content-Type" => "application/json" } }
      else
        body = if decoded =~ /labels.*Priority/i
          page([ { "key" => "PG-1", "fields" => { "summary" => "Epic A",
                                                  "status" => { "name" => "In Progress" },
                                                  "priority" => { "id" => "1" } } } ])
        else
          page([])
        end
        { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
      end
    end

    run = run_sync

    assert run.ok, "board sync should still succeed"
    assert_equal %w[PG-1], Epic.active.pluck(:jira_key)
    assert_equal 0, DiscoveryIdea.count
  end

  test "discovery is skipped entirely when unconfigured" do
    stub_search do |q|
      page([ { "key" => "PG-1", "fields" => { "summary" => "Epic A",
                                              "status" => { "name" => "In Progress" },
                                              "priority" => { "id" => "1" } } } ]) if q =~ /labels.*Priority/i
    end

    JiraSync.new(epic_query: 'project = PG AND labels = "Priority"', unplanned_query: nil,
                 new_unplanned_query: nil, discovery: nil).run!

    assert_equal 0, DiscoveryIdea.count
    assert_equal %w[PG-1], Epic.active.pluck(:jira_key)
  end
end
