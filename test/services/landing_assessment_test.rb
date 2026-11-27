require "test_helper"

class LandingAssessmentTest < ActiveSupport::TestCase
  # Made-up layout and codenames; the real ones live only in the deployment config.
  CALENDAR = LandingCalendar.new(layout: "QYY", codenames: { 426 => "Amber Ant", 127 => "Brave Bear", 227 => "Calm Cat" })
  TODAY = Date.new(2026, 11, 27)

  setup do
    IdeaEvent.delete_all
    IdeaDelivery.delete_all
    DiscoveryIdea.delete_all
  end

  def idea(key = "PGR-1", horizon: "now", time_id: nil, codename: nil, incubator: "Implementation")
    DiscoveryIdea.create!(jira_key: key, summary: "Idea #{key}", horizon: horizon,
                          time_id: time_id, codename: codename, incubator_status: incubator)
  end

  def deliver(idea, todo: 0, in_progress: 0, done: 0, category: "indeterminate", resolved_at: nil)
    idea.idea_deliveries.create!(jira_key: "PG-#{idea.id}", issue_type: "Epic", status_category: category,
                                 todo_count: todo, in_progress_count: in_progress, done_count: done,
                                 resolved_at: resolved_at)
  end

  def event(idea, field, from, to, at)
    IdeaEvent.create!(jira_key: idea.jira_key, field: field, from_value: from, to_value: to,
                      occurred_at: at, author: "Jan")
  end

  def assess(idea, today: TODAY)
    LandingAssessment.new(idea.reload, calendar: CALENDAR, today: today)
  end

  test "no Time-ID means no landing quarter, even with a Codename" do
    a = assess(idea(codename: "Amber Ant"))

    assert_nil a.quarter
    assert_equal :not_set, a.state
    assert_equal "Time-ID not set", a.label
    assert_match(/doesn't guess/, a.explanation)
  end

  test "the Time-ID wins over a Codename that disagrees, and says so" do
    a = assess(idea(time_id: 127, codename: "Amber Ant"))

    assert_equal 127, a.quarter.id
    assert_equal "Time-ID 127 is Brave Bear, but Codename says Amber Ant", a.mismatch
  end

  test "on track when the work keeps up with the quarter" do
    i = idea(time_id: 426, codename: "Amber Ant")
    deliver(i, todo: 1, in_progress: 1, done: 1)

    assert_equal :on_track, assess(i).state
  end

  test "at risk when nothing has started in the target quarter" do
    i = idea(time_id: 426)
    deliver(i, todo: 3)

    a = assess(i)
    assert_equal :at_risk, a.state
    assert_includes a.reasons, "Nothing started"
  end

  test "at risk when progress trails the quarter" do
    i = idea(time_id: 426)
    deliver(i, todo: 10, in_progress: 2)

    a = assess(i)
    assert_equal :at_risk, a.state
    assert_match(/8% done with 62% of the quarter gone/, a.reasons.join)
  end

  test "at risk when targeted this quarter but still in Later" do
    i = idea(time_id: 426, horizon: "later")
    deliver(i, in_progress: 1, done: 3)

    assert_includes assess(i).reasons, "Targets this quarter but the roadmap still has it in Later"
  end

  test "only the current quarter can be at risk; a later one is planned, whatever its horizon" do
    assert_equal :planned, assess(idea("PGR-1", time_id: 227, horizon: "later")).state
    soon = assess(idea("PGR-2", time_id: 127, horizon: "incubator"), today: Date.new(2026, 12, 30))
    assert_equal :planned, soon.state
    assert_empty soon.reasons
  end

  test "late once the quarter is over and it has not landed" do
    i = idea(time_id: 426)
    deliver(i, in_progress: 2)

    a = assess(i, today: Date.new(2027, 1, 15))
    assert_equal :late, a.state
    assert_equal 15, a.late_by
  end

  test "landed on time, or late, by the last delivery's resolution date" do
    on_time = idea("PGR-1", time_id: 426)
    deliver(on_time, done: 4, category: "done", resolved_at: Time.utc(2026, 11, 20))
    late = idea("PGR-2", time_id: 426)
    deliver(late, done: 4, category: "done", resolved_at: Time.utc(2027, 1, 10))

    assert_equal :landed, assess(on_time).state
    a = assess(late, today: Date.new(2027, 2, 1))
    assert_equal :landed_late, a.state
    assert_equal 10, a.late_by
  end

  test "closed without success is dropped" do
    assert_equal :dropped, assess(idea(time_id: 426, horizon: "closed", incubator: "Gone bad")).state
  end

  test "a later Time-ID is a slip and keeps the original target" do
    i = idea(time_id: 227)
    event(i, "time_id", nil, "426", Time.utc(2026, 10, 1))
    event(i, "time_id", "426", "127", Time.utc(2026, 11, 1))
    event(i, "time_id", "127", "227", Time.utc(2026, 11, 20))

    a = assess(i)
    assert_equal %i[set slip slip], a.target_changes.map(&:kind)
    assert_equal 2, a.slips.size
    assert_equal 426, a.baseline.id
  end

  test "a change right after the first target is a correction, not a slip" do
    i = idea(time_id: 127, codename: "Brave Bear")
    event(i, "codename", nil, "Amber Ant", Time.utc(2026, 11, 27, 11, 55))
    event(i, "codename", "Amber Ant", "Brave Bear", Time.utc(2026, 11, 27, 14, 1))

    a = assess(i)
    assert_equal %i[set corrected], a.target_changes.map(&:kind)
    assert_empty a.slips
    assert_equal 127, a.baseline.id
  end

  test "Time-ID history is preferred over Codename history" do
    i = idea(time_id: 127, codename: "Brave Bear")
    event(i, "time_id", nil, "127", Time.utc(2026, 11, 27, 11, 55))
    event(i, "codename", nil, "Amber Ant", Time.utc(2026, 11, 27, 11, 56))
    event(i, "codename", "Amber Ant", "Brave Bear", Time.utc(2026, 12, 20))

    assert_equal %i[set], assess(i).target_changes.map(&:kind)
  end
end
