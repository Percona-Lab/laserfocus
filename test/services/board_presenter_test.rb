require "test_helper"

class BoardPresenterTest < ActiveSupport::TestCase
  fixtures :epics, :issues

  STATUS_MAP = {
    "To Do" => "new",
    "In Progress" => "in_progress",
    "In Review" => "review",
    "Done" => "done"
  }

  def build_presenter(orphan_issues: [], column_order: [], group_mode: :staleness)
    BoardPresenter.new(
      epics: Epic.active.ordered.includes(:issues),
      orphan_issues: orphan_issues,
      column_order: column_order,
      group_mode: group_mode,
      status_map: STATUS_MAP,
      new_statuses: [ "new" ],
      done_statuses: [ "done" ],
      staleness: StalenessCalculator.new(
        now: Time.current, somewhat_days: 7, really_days: 21
      )
    )
  end

  test "columns follow the board order array and exclude removed" do
    cols = build_presenter(column_order: %w[PG-2 PG-1]).columns
    assert_equal %w[PG-2 PG-1], cols.map { |c| c.epic.jira_key }
  end

  test "epics missing from the order append at the end in creation order" do
    cols = build_presenter(column_order: %w[PG-2]).columns
    assert_equal %w[PG-2 PG-1], cols.map { |c| c.epic.jira_key }
  end

  test "columns fall back to creation order when order array is empty" do
    cols = build_presenter.columns
    assert_equal %w[PG-1 PG-2], cols.map { |c| c.epic.jira_key }
  end

  test "stale keys in the order array are ignored" do
    cols = build_presenter(column_order: %w[PG-404 PG-2 PG-1]).columns
    assert_equal %w[PG-2 PG-1], cols.map { |c| c.epic.jira_key }
  end

  test "unplanned column is placed by its sentinel position" do
    orphan = Issue.new(
      jira_key: "PG-99", summary: "Loose ticket", jira_status: "In Progress",
      issue_type: "Task", created_at_jira: 2.days.ago, status_changed_at_jira: 1.day.ago
    )
    cols = build_presenter(orphan_issues: [ orphan ], column_order: %w[PG-1 UNPLANNED PG-2]).columns
    assert_equal %w[PG-1 UNPLANNED PG-2], cols.map { |c| c.epic.jira_key }
  end

  test "issues are grouped by display status with new/done partitioned" do
    cols = build_presenter.columns
    epic1 = cols.first
    assert_equal [ "PG-12" ], epic1.new_issues.map(&:jira_key)
    assert_equal [ "PG-13" ], epic1.done_issues.map(&:jira_key)
    assert_equal [ "PG-10" ], epic1.middle_groups["in_progress"].map(&:jira_key)
    assert_equal [ "PG-11" ], epic1.middle_groups["review"].map(&:jira_key)
  end

  test "issue rows nest same-state subtasks and keep other statuses separate" do
    epic = epics(:priority_one)
    story = Issue.create!(
      jira_key: "PG-20",
      epic: epic,
      issue_type: "Story",
      summary: "Parent story",
      jira_status: "In Progress",
      status_changed_at_jira: 2.hours.ago,
      created_at_jira: 3.hours.ago,
      raw_fields: { "parent" => { "key" => epic.jira_key } }
    )
    Issue.create!(
      jira_key: "PG-21",
      epic: epic,
      issue_type: "Sub-task",
      summary: "Done subtask",
      jira_status: "Done",
      status_changed_at_jira: 1.hour.ago,
      created_at_jira: 2.hours.ago,
      raw_fields: { "parent" => { "key" => story.jira_key } }
    )
    Issue.create!(
      jira_key: "PG-22",
      epic: epic,
      issue_type: "Sub-task",
      summary: "Nested subtask",
      jira_status: "In Progress",
      status_changed_at_jira: 30.minutes.ago,
      created_at_jira: 1.hour.ago,
      raw_fields: { "parent" => { "key" => story.jira_key } }
    )

    column = build_presenter.columns.detect { |col| col.epic.jira_key == epic.jira_key }
    rows = column.issue_rows_for(column.middle_groups["in_progress"])
    story_index = rows.index { |row| row.postit.jira_key == "PG-20" }

    assert_equal "PG-22", rows[story_index + 1].postit.jira_key
    assert_equal 1, rows[story_index + 1].depth
    assert_equal 0, column.issue_rows_for(column.done_issues).detect { |row| row.postit.jira_key == "PG-21" }.depth
  end

  test "warnings include unmapped statuses" do
    warnings = build_presenter.warnings
    assert_includes warnings.map(&:issue_key), "PG-14"
  end

  test "unplanned column defaults to first when absent from the order" do
    orphan = Issue.new(
      jira_key: "PG-99", summary: "Loose ticket", jira_status: "In Progress",
      issue_type: "Task", created_at_jira: 2.days.ago, status_changed_at_jira: 1.day.ago
    )
    cols = build_presenter(orphan_issues: [ orphan ]).columns
    assert_equal %w[UNPLANNED PG-1 PG-2], cols.map { |c| c.epic.jira_key }
    assert_equal [ "PG-99" ], cols.first.all_issues.map(&:jira_key)
  end

  test "unplanned column goes first when the order array lacks the sentinel" do
    orphan = Issue.new(
      jira_key: "PG-99", summary: "Loose ticket", jira_status: "In Progress",
      issue_type: "Task", created_at_jira: 2.days.ago, status_changed_at_jira: 1.day.ago
    )
    cols = build_presenter(orphan_issues: [ orphan ], column_order: %w[PG-2 PG-1]).columns
    assert_equal %w[UNPLANNED PG-2 PG-1], cols.map { |c| c.epic.jira_key }
  end

  test "unplanned column is not rendered when no orphans" do
    cols = build_presenter.columns
    assert_not_includes cols.map { |c| c.epic.jira_key }, "UNPLANNED"
  end

  test "staleness bucket is attached per issue" do
    cols = build_presenter.columns
    by_key = cols.flat_map(&:all_issues).index_by(&:jira_key)
    assert_equal :fresh,    by_key["PG-10"].staleness
    assert_equal :really,   by_key["PG-11"].staleness
    assert_equal :fresh,    by_key["PG-12"].staleness # new + ignore rule
  end

  test "staleness mode orders middle groups by most stale ticket" do
    epic1 = build_presenter.columns.first
    assert_equal %w[review in_progress], epic1.middle_groups.keys
  end

  test "definition mode orders middle groups by status map order" do
    epic1 = build_presenter(group_mode: :definition).columns.first
    assert_equal %w[in_progress review], epic1.middle_groups.keys
  end

  test "definition mode puts unmapped statuses last" do
    epic = epics(:priority_two)
    Issue.create!(
      jira_key: "PG-15",
      epic: epic,
      issue_type: "Task",
      summary: "Mapped middle issue",
      jira_status: "In Progress",
      status_changed_at_jira: 1.day.ago,
      created_at_jira: 2.days.ago,
      raw_fields: {}
    )
    cols = build_presenter(group_mode: :definition).columns
    col = cols.detect { |c| c.middle_groups.key?("unknown") }
    assert_not_nil col, "expected a column containing an unmapped-status issue"
    assert_equal %w[in_progress unknown], col.middle_groups.keys
  end

  test "merged mode produces a single middle group sorted by staleness" do
    epic1 = build_presenter(group_mode: :merged).columns.first
    assert_equal [ BoardPresenter::MERGED_GROUP ], epic1.middle_groups.keys
    assert_equal %w[PG-11 PG-10], epic1.middle_groups[BoardPresenter::MERGED_GROUP].map(&:jira_key)
  end

  test "merged mode nests subtasks across middle statuses" do
    epic = epics(:priority_one)
    Issue.create!(
      jira_key: "PG-30", epic: epic, issue_type: "Story", summary: "Parent story",
      jira_status: "In Progress", status_changed_at_jira: 2.hours.ago,
      created_at_jira: 3.hours.ago, raw_fields: {}
    )
    Issue.create!(
      jira_key: "PG-31", epic: epic, issue_type: "Sub-task", summary: "Child in review",
      jira_status: "In Review", status_changed_at_jira: 1.hour.ago,
      created_at_jira: 2.hours.ago, raw_fields: { "parent" => { "key" => "PG-30" } }
    )

    column = build_presenter(group_mode: :merged).columns.detect { |c| c.epic.jira_key == epic.jira_key }
    rows = column.issue_rows_for(column.middle_groups[BoardPresenter::MERGED_GROUP])
    i = rows.index { |r| r.postit.jira_key == "PG-30" }

    assert_equal "PG-31", rows[i + 1].postit.jira_key
    assert_equal 1, rows[i + 1].depth
  end

  test "merged mode leaves new and done partitions untouched" do
    epic1 = build_presenter(group_mode: :merged).columns.first
    assert_equal [ "PG-12" ], epic1.new_issues.map(&:jira_key)
    assert_equal [ "PG-13" ], epic1.done_issues.map(&:jira_key)
  end
end
