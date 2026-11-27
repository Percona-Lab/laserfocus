require "test_helper"
require "webmock/minitest"

class JiraSyncLandingTest < ActiveSupport::TestCase
  DISCOVERY = LaserFocus::Config::DiscoverySection.new(
    "now_query"  => 'project = PGR AND cf[11275] = "Now"',
    "next_query" => 'project = PGR AND cf[11275] = "Next"',
    "roadmap_query" => "project = PGR AND issuetype = Idea",
    "delivery_link_type_id" => "10016",
    "horizon_field"   => "customfield_11275",
    "incubator_field" => "customfield_11290",
    "rank_field"      => "customfield_10019",
    "time_id_field"   => "customfield_11385",
    "codename_field"  => "customfield_11386",
    "time_id_layout"  => "QYY"
  )

  setup do
    WebMock.disable_net_connect!
    IdeaEvent.delete_all
    IdeaDelivery.delete_all
    DiscoveryIdea.delete_all
    Issue.delete_all
    Epic.delete_all
    stub_request(:get, %r{/dev-status}).to_return(
      status: 200, body: '{"errors":[],"detail":[]}', headers: { "Content-Type" => "application/json" }
    )
  end

  def page(issues) = { "issues" => issues, "total" => issues.size, "startAt" => 0, "maxResults" => 50 }

  def history(at, field_id, field, from, to)
    { "created" => at, "author" => { "displayName" => "Jan" },
      "items" => [ { "field" => field, "fieldId" => field_id, "fromString" => from, "toString" => to } ] }
  end

  def pgr17(horizon: "Now")
    { "key" => "PGR-17", "fields" => {
        "summary" => "TDE: Integration with AWS",
        "customfield_11275" => { "value" => horizon },
        "customfield_11290" => { "value" => "Implementation" },
        "customfield_11385" => 127.0,
        "customfield_11386" => { "value" => "Brave Bear" },
        "issuelinks" => [ { "type" => { "id" => "10016" },
                            "inwardIssue" => { "key" => "PG-1402", "fields" => { "issuetype" => { "name" => "Epic" } } } } ]
      },
      "changelog" => { "histories" => [
        history("2026-11-27T14:01:30.970+0000", "customfield_11386", "Codename", "Amber Ant", "Brave Bear"),
        history("2026-11-27T11:55:35.367+0000", "customfield_11386", "Codename", nil, "Amber Ant"),
        history("2026-11-27T11:55:32.946+0000", "customfield_11385", "Time-ID", nil, "127"),
        history("2026-09-18T13:34:29.349+0000", "customfield_11275", "Roadmap", "Next", "Now"),
        history("2026-09-01T10:00:00.000+0000", "customfield_11290", "Incubator status", "Committed", "Implementation")
      ] } }
  end

  def later_idea
    { "key" => "PGR-61", "fields" => {
        "summary" => "Expand analytics offering",
        "customfield_11275" => { "value" => "Later" },
        "customfield_11386" => { "value" => "Amber Ant" },
        "issuelinks" => []
      } }
  end

  def stub_jira
    stub_request(:get, %r{/search}).to_return do |req|
      q = CGI.unescape(req.uri.to_s)
      body = if q.include?("issuetype = Idea") then page([ pgr17, later_idea ])
      elsif q.include?('"Now"') then page([ pgr17 ])
      elsif q =~ /key in \("PG-1402"\)/ && !q.include?("issuetype = Epic")
        page([ { "key" => "PG-1402", "fields" => {
          "summary" => "TDE: Integration with AWS",
          "status" => { "name" => "In Progress", "statusCategory" => { "key" => "indeterminate" } },
          "created" => "2025-03-06T10:00:00.000+0000", "resolutiondate" => nil } } ])
      elsif q.include?('parent in ("PG-1402")')
        page(%w[indeterminate indeterminate done].each_with_index.map do |cat, i|
          { "key" => "PG-#{3000 + i}", "fields" => { "status" => { "statusCategory" => { "key" => cat } },
                                                     "parent" => { "key" => "PG-1402" } } }
        end)
      else page([])
      end
      { status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end
  end

  def run_sync
    JiraSync.new(epic_query: 'project = PG AND labels = "Priority"', unplanned_query: nil,
                 new_unplanned_query: nil, discovery: DISCOVERY).run!
  end

  test "stores the Time-ID and Codename of every idea, whatever its horizon" do
    stub_jira
    run_sync

    pgr17 = DiscoveryIdea.find_by(jira_key: "PGR-17")
    assert_equal 127, pgr17.time_id
    assert_equal "Brave Bear", pgr17.codename
    assert_equal "now", pgr17.horizon

    later = DiscoveryIdea.find_by(jira_key: "PGR-61")
    assert_equal "later", later.horizon
    assert_nil later.time_id
    assert_equal "Amber Ant", later.codename
  end

  test "copies target and horizon changes from the changelog once" do
    stub_jira
    run_sync
    run_sync

    events = IdeaEvent.where(jira_key: "PGR-17").chronological
    assert_equal [ %w[horizon Next Now], [ "time_id", nil, "127" ], [ "codename", nil, "Amber Ant" ],
                   [ "codename", "Amber Ant", "Brave Bear" ] ],
                 events.map { |e| [ e.field, e.from_value, e.to_value ] }
    assert_equal "Jan", events.first.author
  end

  test "reads delivery progress for targeted ideas, on the board or not" do
    stub_jira
    run_sync

    d = IdeaDelivery.find_by(jira_key: "PG-1402")
    assert_equal "In Progress", d.status_name
    assert_equal "indeterminate", d.status_category
    assert_equal [ 0, 2, 1 ], [ d.todo_count, d.in_progress_count, d.done_count ]
  end

  test "the board judges the idea by its Time-ID" do
    stub_jira
    run_sync

    board = LandingBoard.build(today: Date.new(2026, 11, 27), discovery: DISCOVERY)
    a = board.for_epic("PG-1402")
    assert_equal 127, a.quarter.id
    assert_equal :planned, a.state
    assert_empty a.slips, "the Codename fix came minutes after the Time-ID was set"

    findings = board.findings
    assert(findings.any? { |f| f.kind == :no_time_id && f.key == "PGR-61" })
  end
end
