# Everything the Reviews view shows: the PRs grouped by review stage, each with
# its waiting clock, staleness, "decision needed" flag and snooze.
class ReviewsPresenter
  include GithubViewPresenter

  STAGES = [
    { id: "needs",    label: "Needs review",      color: "#8b5cf6", step: 0 },
    { id: "discuss",  label: "In discussion",     color: "#3b82f6", step: 1 },
    { id: "changes",  label: "Changes requested", color: "#ec4899", step: 1 },
    { id: "approved", label: "Approved",          color: "#22c55e", step: 2 }
  ].freeze
  WAITING_LABEL = { "reviewers" => "reviewers", "author" => "the author", "merge" => "whoever merges" }.freeze

  # Wording for the shared header (see shared/_header_tools).
  COPY = {
    noun: "PR", nouns: "PRs",
    all_hint: "Every PR that is ready for review",
    needs_me_hint: "Review requested from you, or you reviewed and the author has pushed since",
    mine_hint: "PRs you wrote, replied to or are asked to review, like ticking your name under People",
    people_hint: "Filter by who wrote, replied to or is asked to review a PR",
    roles: { "any" => "Are involved", "author" => "Wrote it", "replied" => "Replied", "requested" => "Are asked" },
    wrote: "wrote", replied: "replied", asked: "asked",
    no_reply_hint: "Nobody but the author has commented or reviewed",
    community_hint: "Only PRs from people outside the org: first-time and returning contributors",
    empty_repo: "No open PRs ready for review"
  }.freeze

  Card = Struct.new(:pr, :days, :age_days, :staleness, :decision, :snooze, :fresh_ready, keyword_init: true) do
    delegate :repo, :number, :key, :title, :author, :stage, :waiting_on, to: :pr
    def item = pr
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
  # see GithubViewer. excluded: the repos the viewer took out of their view.
  def self.build(viewer: nil, excluded: Set.new, now: Time.current)
    viewer ||= {}
    prs = ReviewPullRequest.all.to_a
    people = ReviewPeople.from_prs(prs, viewer_names: viewer[:names] || [ viewer[:name] ], viewer_github: viewer[:github])
    new(prs: prs, snoozes: StaleSnooze.running(now).to_a, people: people, now: now, viewer: viewer, excluded: excluded)
  end

  # Cheap enough for every page: the red count on the Reviews tab.
  def self.critical_count(excluded: Set.new, now: Time.current)
    return 0 unless LASER_FOCUS_CONFIG.reviews
    build(excluded: excluded, now: now).cards.count { |c| c.staleness == :really }
  end

  def initialize(prs:, snoozes: [], people: nil, now: Time.current, viewer: {}, excluded: Set.new,
                 config: LASER_FOCUS_CONFIG.reviews, lead: LASER_FOCUS_CONFIG.board.staleness_lead)
    @prs, @hidden = split_excluded(prs, excluded)
    @snoozes = snoozes.index_by { |s| s.jira_key.downcase }
    @people = people || ReviewPeople.from_prs(prs)
    @now = now
    @config = config
    @lead = lead
    @viewer = viewer
  end

  def cards
    @cards ||= @prs.map { |pr| card_for(pr) }
  end

  # Most stale first, like the board's Staleness mode; snoozed ones sink.
  def columns
    @columns ||= STAGES.map do |stage|
      list = cards.select { |c| c.stage == stage[:id] }
                  .sort_by { |c| [ c.snoozed? ? 1 : 0, -c.days, c.repo.downcase, c.number ] }
      Column.new(stage: stage, cards: list)
    end
  end

  def thresholds(waiting_on)
    if waiting_on == "author"
      [ @config.author_somewhat_days, @config.author_really_days ]
    else
      [ @config.somewhat_days, @config.really_days ]
    end
  end

  # Review requested from the viewer, or the viewer reviewed and the author has
  # pushed since.
  def needs_viewer?(card)
    pr = card.pr
    return false if @people.me?(pr.author)
    return true if pr.requested_list.any? { |l| @people.me?(l) }
    pr.waiting_on == "reviewers" && pr.review_list.any? { |r| @people.me?(r["login"]) }
  end

  def copy = COPY
  def display(login) = @people.display(login)

  def waiting_label(waiting_on) = WAITING_LABEL.fetch(waiting_on, waiting_on)

  private

  def card_for(pr)
    days = whole_days(pr.waiting_since)
    age_days = whole_days(pr.ready_at || pr.opened_at)
    somewhat, really = thresholds(pr.waiting_on)
    bucket = bucket_for(days, somewhat, really)
    decision = age_days >= @config.decision_days
    snooze = @snoozes[pr.key.downcase]
    snooze = nil unless snooze && snooze.snoozed_until > @now && snooze.jira_status == pr.snooze_state
    snoozed = snooze && (bucket != :fresh || decision)
    Card.new(
      pr: pr, days: days, age_days: age_days,
      staleness: snoozed ? :snoozed : bucket,
      decision: decision && !snoozed,
      snooze: snoozed ? snooze : nil,
      fresh_ready: pr.stage == "needs" && (pr.ready_at || pr.opened_at) > @now - 1.day
    )
  end
end
