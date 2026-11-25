# Everything the Issues view shows: the open issues grouped by who has the
# ball, each with its waiting clock, staleness, "decision needed" flag and
# snooze. The People filter, scope pills and counts work as on Reviews.
class IssuesPresenter
  include GithubViewPresenter

  STAGES = [
    { id: "new",      label: "New",                 color: "#8b5cf6", tag: [ "no reply from the team", "kb-col-tag-reviewers" ] },
    { id: "us",       label: "Waiting on us",       color: "#3b82f6", tag: [ "on the team", "kb-col-tag-reviewers" ] },
    { id: "reporter", label: "Waiting on reporter", color: "#ec4899", tag: [ "on the reporter", "kb-col-tag-author" ] },
    { id: "backlog",  label: "Team backlog",        color: "#64748b", tag: [ "filed by the team", nil ] }
  ].freeze
  # Which thresholds (see LaserFocus::Config::IssuesSection) each column uses.
  CLOCK = { "new" => "team", "us" => "team", "reporter" => "reporter", "backlog" => "backlog" }.freeze
  WAITING_LABEL = { "team" => "the team", "reporter" => "the reporter" }.freeze

  # Wording for the shared header (see shared/_header_tools).
  COPY = {
    noun: "issue", nouns: "issues",
    all_hint: "Every open issue",
    needs_me_hint: "Assigned to you and waiting on the team",
    mine_hint: "Issues you opened, commented on or are assigned to, like ticking your name under People",
    people_hint: "Filter by who opened, commented on or is assigned to an issue",
    roles: { "any" => "Are involved", "author" => "Opened it", "replied" => "Commented", "requested" => "Assigned" },
    wrote: "opened", replied: "commented", asked: "assigned",
    no_reply_hint: "Nobody but the reporter has commented",
    community_hint: "Only issues from people outside the org",
    empty_repo: "No open issues"
  }.freeze

  Card = Struct.new(:issue, :days, :age_days, :staleness, :decision, :snooze, :fresh, keyword_init: true) do
    delegate :repo, :number, :key, :title, :author, :stage, :waiting_on, to: :issue
    def item = issue
    def stale? = %i[somewhat really].include?(staleness)
    def snoozed? = staleness == :snoozed
    def decision? = decision
    # Right-click opens the snooze menu for these.
    def snoozable? = stale? || decision? || snoozed?
  end

  Column = Struct.new(:stage, :cards, keyword_init: true) do
    def id = stage[:id]
    def stale_count = cards.count(&:stale?)
    def snoozed_count = cards.count(&:snoozed?)
    def decision_count = cards.count(&:decision?)
  end

  # viewer: { names:, github:, google_name:, email: } for the signed-in person,
  # see GithubViewer.
  def self.build(viewer: nil, now: Time.current)
    viewer ||= {}
    issues = GithubIssue.all.to_a
    people = ReviewPeople.from_prs(issues, viewer_names: viewer[:names] || [ viewer[:name] ], viewer_github: viewer[:github])
    new(issues: issues, snoozes: StaleSnooze.running(now).to_a, people: people, now: now, viewer: viewer)
  end

  # Cheap enough for every page: the red count on the Issues tab. Every card
  # past its column's critical threshold counts, whoever has the ball.
  def self.critical_count(now: Time.current)
    return 0 unless LASER_FOCUS_CONFIG.issues
    build(now: now).cards.count { |c| c.staleness == :really }
  end

  def initialize(issues:, snoozes: [], people: nil, now: Time.current, viewer: {},
                 config: LASER_FOCUS_CONFIG.issues, lead: LASER_FOCUS_CONFIG.board.staleness_lead)
    @issues = issues
    @snoozes = snoozes.index_by { |s| s.jira_key.downcase }
    @people = people || ReviewPeople.from_prs(issues)
    @now = now
    @config = config
    @lead = lead
    @viewer = viewer
  end

  def copy = COPY

  def cards
    @cards ||= @issues.map { |issue| card_for(issue) }
  end

  # Most stale first; snoozed ones sink.
  def columns
    @columns ||= STAGES.map do |stage|
      list = cards.select { |c| c.stage == stage[:id] }
                  .sort_by { |c| [ c.snoozed? ? 1 : 0, -c.days, c.repo.downcase, c.number ] }
      Column.new(stage: stage, cards: list)
    end
  end

  def thresholds(stage_id) = @config.thresholds(CLOCK.fetch(stage_id))
  def decision_days = @config.decision_days

  # Assigned to the viewer, and the ball is with the team.
  def needs_viewer?(card)
    card.waiting_on == "team" && card.issue.assignee_list.any? { |l| @people.me?(l) }
  end

  def waiting_label(waiting_on) = WAITING_LABEL.fetch(waiting_on, waiting_on)
  def display(login) = @people.display(login)

  private

  def card_for(issue)
    days = whole_days(issue.waiting_since)
    age_days = whole_days(issue.opened_at)
    somewhat, really = thresholds(issue.stage)
    bucket = bucket_for(days, somewhat, really)
    decision = age_days >= @config.decision_days
    snooze = @snoozes[issue.key.downcase]
    snooze = nil unless snooze && snooze.snoozed_until > @now && snooze.jira_status == issue.snooze_state
    snoozed = snooze && (bucket != :fresh || decision)
    Card.new(
      issue: issue, days: days, age_days: age_days,
      staleness: snoozed ? :snoozed : bucket,
      decision: decision && !snoozed,
      snooze: snoozed ? snooze : nil,
      fresh: issue.opened_at > @now - 1.day
    )
  end
end
