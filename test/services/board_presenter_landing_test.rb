require "test_helper"

class BoardPresenterLandingTest < ActiveSupport::TestCase
  fixtures :epics, :issues

  # Made-up layout; the real one lives only in the deployment config.
  CALENDAR = LandingCalendar.new(layout: "QYY")

  setup do
    IdeaEvent.delete_all
    IdeaDelivery.delete_all
    DiscoveryIdea.delete_all
  end

  def idea(key, delivers:, time_id: nil, horizon: "now")
    i = DiscoveryIdea.create!(jira_key: key, summary: "Idea #{key}", horizon: horizon, time_id: time_id)
    i.idea_deliveries.create!(jira_key: delivers, issue_type: "Epic", status_category: "indeterminate",
                              in_progress_count: 1, done_count: 1)
    i
  end

  def build(column_sort:, column_order: %w[PG-1 PG-2])
    landing = LandingBoard.new(ideas: DiscoveryIdea.active.includes(:idea_deliveries, :idea_events).to_a,
                               today: Date.new(2026, 11, 27), calendar: CALENDAR)
    BoardPresenter.new(
      epics: Epic.active.ordered.includes(:issues),
      column_order: column_order,
      now_ideas: DiscoveryIdea.now.includes(:idea_deliveries).to_a,
      column_sort: column_sort,
      landing: landing,
      status_map: { "To Do" => "new", "In Progress" => "in_progress", "In Review" => "review", "Done" => "done" },
      new_statuses: [ "new" ],
      done_statuses: [ "done" ],
      staleness: StalenessCalculator.new(now: Time.current, somewhat_days: 7, really_days: 21)
    )
  end

  test "each column carries the landing assessment of the idea it delivers" do
    idea("PGR-17", delivers: "PG-1", time_id: 127)

    col = build(column_sort: :manual).columns.find { |c| c.epic.jira_key == "PG-1" }
    assert_equal 127, col.landing.quarter.id
    assert_nil build(column_sort: :manual).columns.find { |c| c.epic.jira_key == "PG-2" }.landing
  end

  test "by landing puts the earliest quarter first, regardless of the drag order" do
    idea("PGR-17", delivers: "PG-1", time_id: 127)
    idea("PGR-39", delivers: "PG-2", time_id: 426)

    assert_equal %w[PG-1 PG-2], build(column_sort: :manual).columns.map { |c| c.epic.jira_key }
    presenter = build(column_sort: :landing)
    assert_equal %w[PG-2 PG-1], presenter.columns.map { |c| c.epic.jira_key }
    assert_equal [ 426, 127 ], presenter.column_groups.map { |g| presenter.landing_lane(g.first).id }
  end

  test "an idea without a Time-ID gets its own lane after the quarters" do
    idea("PGR-41", delivers: "PG-1")
    idea("PGR-39", delivers: "PG-2", time_id: 426)

    presenter = build(column_sort: :landing)
    assert_equal %w[PG-2 PG-1], presenter.columns.map { |c| c.epic.jira_key }
    assert_equal :not_set, presenter.landing_lane(presenter.columns.last)
  end

  test "the roadmap line summarises the current quarter and raises the notices" do
    idea("PGR-39", delivers: "PG-2", time_id: 426)
    idea("PGR-41", delivers: "PG-1")

    alignment = build(column_sort: :manual).alignment
    assert_equal 426, alignment.landing_summary.quarter.id
    assert_equal 1, alignment.landing_summary.targeted
    assert(alignment.findings.any? { |f| f.kind == :no_time_id && f.key == "PGR-41" })
  end

  test "without landing quarters configured the order stays manual" do
    presenter = BoardPresenter.new(
      epics: Epic.active.ordered.includes(:issues), column_order: %w[PG-2 PG-1], column_sort: :landing,
      status_map: { "To Do" => "new" }, new_statuses: [ "new" ], done_statuses: [ "done" ],
      staleness: StalenessCalculator.new(now: Time.current, somewhat_days: 7, really_days: 21)
    )
    refute presenter.landing_sort?
    assert_equal %w[PG-2 PG-1], presenter.columns.map { |c| c.epic.jira_key }
  end
end
