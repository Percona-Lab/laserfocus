require "test_helper"

class StaleSnoozeTest < ActiveSupport::TestCase
  fixtures :epics, :issues

  def snooze_for(issue, until_at: 3.days.from_now, status: issue.jira_status)
    StaleSnooze.create!(jira_key: issue.jira_key, jira_status: status,
                        snoozed_until: until_at, snoozed_by: "Alice")
  end

  test "applies while running and in the status it was snoozed in" do
    issue = issues(:stale_in_review)
    assert snooze_for(issue).applies_to?(issue)
  end

  test "does not apply once it has run out" do
    issue = issues(:stale_in_review)
    snooze = snooze_for(issue, until_at: 3.days.from_now)
    assert_not snooze.applies_to?(issue, now: 4.days.from_now)
  end

  test "does not apply after the ticket changed status" do
    issue = issues(:stale_in_review)
    snooze = snooze_for(issue, status: "In Progress")
    assert_not snooze.applies_to?(issue)
  end

  test "running excludes expired snoozes" do
    snooze_for(issues(:stale_in_review), until_at: 1.hour.ago)
    snooze_for(issues(:fresh_in_progress))
    assert_equal [ "PG-10" ], StaleSnooze.running.pluck(:jira_key)
  end

  test "days_left rounds up to whole days" do
    snooze = snooze_for(issues(:stale_in_review), until_at: 7.days.from_now)
    assert_equal 7, snooze.days_left
    assert_equal 1, snooze.days_left(now: 6.days.from_now + 1.hour)
  end

  test "reason is limited in length" do
    snooze = StaleSnooze.new(jira_key: "PG-11", jira_status: "In Review", snoozed_until: 1.day.from_now,
                             snoozed_by: "Alice", reason: "x" * (StaleSnooze::REASON_LIMIT + 1))
    assert_not snooze.valid?
  end

  test "prune drops expired, moved and vanished tickets and keeps the rest" do
    snooze_for(issues(:stale_in_review))                                  # kept
    snooze_for(issues(:fresh_in_progress), until_at: 1.minute.ago)        # expired
    snooze_for(issues(:done_one), status: "In Review")                    # moved on
    StaleSnooze.create!(jira_key: "PG-404", jira_status: "In Review",     # gone from the board
                        snoozed_until: 2.days.from_now, snoozed_by: "Alice")

    StaleSnooze.prune!
    assert_equal [ "PG-11" ], StaleSnooze.pluck(:jira_key)
  end
end
