require "set"

class BoardPresenter
  Warning = Struct.new(:issue_key, :status, :reason)
  IssueRow = Struct.new(:postit, :depth)

  IssuePresenter = Struct.new(:issue, :display_status, :staleness) do
    def jira_key        = issue.jira_key
    def summary         = issue.summary
    def assignee        = issue.assignee_username
    def jira_status     = issue.jira_status
    def issue_type      = issue.issue_type
    def priority        = issue.priority
    def parent_jira_key = issue.parent_jira_key
    def labels          = issue.labels
    def components      = issue.components
    def epic_id          = issue.epic_id
    def provisional      = issue.provisional
    def pull_requests    = issue.pull_requests
    def description      = issue.description
    def description_html = issue.description_html
    def created_at_jira = issue.created_at_jira
    def status_changed_at_jira = issue.status_changed_at_jira
    def transitioned_at = issue.status_changed_at_jira || issue.created_at_jira
  end

  Column = Struct.new(:epic, :new_issues, :middle_groups, :done_issues) do
    def all_issues
      new_issues + middle_groups.values.flatten + done_issues
    end

    def merged_middle? = middle_groups.key?(BoardPresenter::MERGED_GROUP)

    def issue_rows_for(postits)
      issue_keys = Set.new(postits.map(&:jira_key))
      children_by_parent = Hash.new { |h, k| h[k] = [] }
      child_keys = Set.new

      postits.each do |postit|
        parent_key = postit.parent_jira_key
        next if parent_key.blank? || !issue_keys.include?(parent_key)

        children_by_parent[parent_key] << postit
        child_keys << postit.jira_key
      end

      postits.each_with_object([]) do |postit, rows|
        next if child_keys.include?(postit.jira_key)

        rows << IssueRow.new(postit, 0)
        children_by_parent[postit.jira_key].each do |child|
          rows << IssueRow.new(child, 1)
        end
      end
    end
  end

  UNPLANNED_EPIC = Struct.new(:jira_key, :name).new("UNPLANNED", "Unplanned Work")
  GROUP_MODES = %w[staleness definition merged].freeze
  DEFAULT_GROUP_MODE = "staleness".freeze
  MERGED_GROUP = "merged".freeze

  def self.build(config: LASER_FOCUS_CONFIG.board, group_mode: :staleness)
    new(
      epics: Epic.active.ordered.includes(:issues),
      orphan_issues: Issue.active.orphan,
      column_order: BoardOrder.instance.column_order,
      group_mode: group_mode,
      status_map: config.status_map,
      new_statuses: config.new_statuses,
      done_statuses: config.done_statuses,
      staleness: StalenessCalculator.new(
        now: Time.current,
        somewhat_days: config.staleness.somewhat_days,
        really_days: config.staleness.really_days,
        ignore_for_new: config.ignore_staleness_for_new_issues,
        new_display_statuses: config.new_statuses,
        done_display_statuses: config.done_statuses
      )
    )
  end

  def initialize(epics:, status_map:, new_statuses:, done_statuses:, staleness:, orphan_issues: [], column_order: [], group_mode: :staleness)
    @epics = epics
    @orphan_issues = orphan_issues
    @column_order = column_order
    @group_mode = group_mode.to_sym
    @status_map = status_map
    @new_statuses = new_statuses
    @done_statuses = done_statuses
    @staleness = staleness
    @warnings = []
  end

  def columns
    @columns ||= begin
      cols = @epics.map { |e| build_column(e, e.issues.reject { |i| i.removed_at }) }
      orphans = @orphan_issues.reject { |i| i.removed_at }
      cols << build_column(UNPLANNED_EPIC, orphans) if orphans.any?
      sort_columns(cols)
    end
  end

  def configured_display_statuses
    @configured_display_statuses ||= @status_map.values.uniq
  end

  def warnings
    columns # force build
    @warnings
  end

  private

  def sort_columns(cols)
    index = {}
    @column_order.each_with_index { |key, i| index[key] = i }
    listed, missing = cols.partition { |c| index.key?(c.epic.jira_key) }
    unplanned, fresh = missing.partition { |c| c.epic.jira_key == UNPLANNED_EPIC.jira_key }
    unplanned + listed.sort_by { |c| index[c.epic.jira_key] } + fresh
  end

  def build_column(epic, issues)
    presented = issues.map { |i| present(i) }
    sorted = presented.sort_by { |p| p.transitioned_at || Time.at(0) }

    new_group  = sorted.select { |p| @new_statuses.include?(p.display_status) }
    done_group = sorted.select { |p| @done_statuses.include?(p.display_status) }
    middle     = sorted - new_group - done_group
    middle_groups = group_middle(middle)

    Column.new(epic, new_group, middle_groups, done_group)
  end

  def group_middle(middle)
    case @group_mode
    when :merged
      middle.empty? ? {} : { MERGED_GROUP => middle }
    when :definition
      middle.group_by(&:display_status)
            # index tiebreak: sort_by is not stability-guaranteed
            .sort_by.with_index { |(status, _), i| [ definition_order.fetch(status, definition_order.size), i ] }
            .to_h
    else
      middle.group_by(&:display_status)
    end
  end

  def definition_order
    @definition_order ||= configured_display_statuses.each_with_index.to_h
  end

  def present(issue)
    display = @status_map[issue.jira_status]
    if display.nil?
      @warnings << Warning.new(issue.jira_key, issue.jira_status, "unmapped")
      display = "unknown"
    end
    bucket = @staleness.bucket(
      transitioned_at: issue.status_changed_at_jira || issue.created_at_jira,
      display_status: display
    )
    IssuePresenter.new(issue, display, bucket)
  end
end
