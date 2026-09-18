require "test_helper"

class BoardPresenterTest < ActiveSupport::TestCase
  fixtures :epics, :issues

  STATUS_MAP = {
    "To Do" => "new",
    "In Progress" => "in_progress",
    "In Review" => "review",
    "Done" => "done"
  }

  def build_presenter(orphan_issues: [], column_order: [], group_mode: :staleness, collapsed_keys: [],
                      expand_all: false, ongoing_label: nil, now_ideas: [])
    BoardPresenter.new(
      epics: Epic.active.ordered.includes(:issues),
      orphan_issues: orphan_issues,
      column_order: column_order,
      collapsed_keys: collapsed_keys,
      expand_all: expand_all,
      ongoing_label: ongoing_label,
      now_ideas: now_ideas,
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

  test "columns carry the stored collapsed flag" do
    cols = build_presenter(collapsed_keys: %w[PG-2]).columns
    assert_equal [ false, true ], cols.map(&:collapsed)
  end

  test "column_groups keeps expanded columns as singletons" do
    groups = build_presenter.column_groups
    assert_equal [ %w[PG-1], %w[PG-2] ], groups.map { |g| g.map { |c| c.epic.jira_key } }
  end

  test "column_groups stacks adjacent collapsed columns" do
    groups = build_presenter(collapsed_keys: %w[PG-1 PG-2]).column_groups
    assert_equal [ %w[PG-1 PG-2] ], groups.map { |g| g.map { |c| c.epic.jira_key } }
  end

  test "column_groups does not stack collapsed columns separated by an expanded one" do
    orphan = Issue.new(
      jira_key: "PG-99", summary: "Loose ticket", jira_status: "In Progress",
      issue_type: "Task", created_at_jira: 2.days.ago, status_changed_at_jira: 1.day.ago
    )
    groups = build_presenter(orphan_issues: [ orphan ], column_order: %w[UNPLANNED PG-1 PG-2],
                             collapsed_keys: %w[UNPLANNED PG-2]).column_groups
    assert_equal [ %w[UNPLANNED], %w[PG-1], %w[PG-2] ], groups.map { |g| g.map { |c| c.epic.jira_key } }
    assert_equal [ true, false, true ], groups.flatten.map(&:collapsed)
  end

  test "expand_all renders every column alone but keeps the stored flag" do
    presenter = build_presenter(collapsed_keys: %w[PG-1 PG-2], expand_all: true)
    assert presenter.expand_all?
    assert_equal [ %w[PG-1], %w[PG-2] ], presenter.column_groups.map { |g| g.map { |c| c.epic.jira_key } }
    assert_equal [ true, true ], presenter.columns.map(&:collapsed)
  end

  test "provisional orphan is surfaced in the unplanned new group" do
    issue = Issue.create!(jira_key: "PG-600", epic: nil, issue_type: "Task",
                          summary: "New one", jira_status: "To Do", provisional: true)

    presenter = BoardPresenter.new(
      epics: [], orphan_issues: [ issue ],
      status_map: { "To Do" => "new" }, new_statuses: [ "new" ], done_statuses: [ "done" ],
      staleness: StalenessCalculator.new(
        now: Time.current, somewhat_days: 3, really_days: 10,
        ignore_for_new: true, new_display_statuses: [ "new" ], done_display_statuses: [ "done" ]
      )
    )

    unplanned = presenter.columns.find { |c| c.epic.jira_key == BoardPresenter::UNPLANNED_EPIC.jira_key }
    assert_not_nil unplanned
    row = unplanned.new_issues.first
    assert_equal "PG-600", row.jira_key
    assert_equal true, row.provisional
  end

  # ---------- lanes ----------

  def now_idea(key, delivery_keys)
    idea = DiscoveryIdea.create!(jira_key: key, summary: "Idea #{key}", horizon: "now")
    delivery_keys.each { |k| idea.idea_deliveries.create!(jira_key: k, issue_type: "Epic") }
    idea
  end

  test "an epic with tickets in flight is focus" do
    col = build_presenter.columns.find { |c| c.epic.jira_key == "PG-1" }
    assert_equal :focus, col.lane
  end

  test "the ongoing label wins over everything else" do
    epics(:priority_one).update!(raw_fields: { "labels" => [ "Ongoing" ] })
    col = build_presenter(ongoing_label: "Ongoing").columns.find { |c| c.epic.jira_key == "PG-1" }
    assert_equal :ongoing, col.lane
  end

  test "an epic with nothing in flight and no roadmap item is parked" do
    Issue.where(jira_key: %w[PG-10 PG-11]).update_all(jira_status: "To Do")
    col = build_presenter.columns.find { |c| c.epic.jira_key == "PG-1" }
    assert_equal :parked, col.lane
  end

  test "an epic whose own status is in progress stays focus with nothing in flight" do
    Issue.where(jira_key: %w[PG-10 PG-11]).update_all(jira_status: "To Do")
    epics(:priority_one).update!(
      raw_fields: { "status" => { "statusCategory" => { "key" => "indeterminate" } } }
    )
    col = build_presenter.columns.find { |c| c.epic.jira_key == "PG-1" }
    assert_equal :focus, col.lane
  end

  test "a Now commitment makes an idle epic focus and attaches the idea" do
    Issue.where(jira_key: %w[PG-10 PG-11]).update_all(jira_status: "To Do")
    idea = now_idea("PGR-1", %w[PG-1])

    col = build_presenter(now_ideas: [ idea ]).columns.find { |c| c.epic.jira_key == "PG-1" }

    assert_equal :focus, col.lane
    assert_equal "PGR-1", col.roadmap_idea.jira_key
  end

  test "columns with no roadmap item carry no idea" do
    idea = now_idea("PGR-1", %w[PG-1])
    col = build_presenter(now_ideas: [ idea ]).columns.find { |c| c.epic.jira_key == "PG-2" }
    assert_nil col.roadmap_idea
  end
end
