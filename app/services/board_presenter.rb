class BoardPresenter
  Warning = Struct.new(:issue_key, :status, :reason)

  IssuePresenter = Struct.new(:issue, :display_status, :staleness) do
    def jira_key        = issue.jira_key
    def summary         = issue.summary
    def assignee        = issue.assignee_username
    def jira_status     = issue.jira_status
    def issue_type      = issue.issue_type
    def priority        = issue.priority
    def created_at_jira = issue.created_at_jira
    def status_changed_at_jira = issue.status_changed_at_jira
    def transitioned_at = issue.status_changed_at_jira || issue.created_at_jira
  end

  Column = Struct.new(:epic, :new_issues, :middle_groups, :done_issues) do
    def all_issues
      new_issues + middle_groups.values.flatten + done_issues
    end
  end

  UNPLANNED_EPIC = Struct.new(:jira_key, :name).new("UNPLANNED", "Unplanned")

  def initialize(epics:, status_map:, new_statuses:, done_statuses:, staleness:, orphan_issues: [])
    @epics = epics
    @orphan_issues = orphan_issues
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
      cols.unshift(build_column(UNPLANNED_EPIC, orphans)) if orphans.any?
      cols
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

  def build_column(epic, issues)
    presented = issues.map { |i| present(i) }
    sorted = presented.sort_by { |p| p.transitioned_at || Time.at(0) }

    new_group  = sorted.select { |p| @new_statuses.include?(p.display_status) }
    done_group = sorted.select { |p| @done_statuses.include?(p.display_status) }
    middle     = sorted - new_group - done_group
    middle_groups = middle.group_by(&:display_status)

    Column.new(epic, new_group, middle_groups, done_group)
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
