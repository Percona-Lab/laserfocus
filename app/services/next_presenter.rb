# The "Next" view is about readiness, not progress: nothing here has started, so
# the only useful question is whether we could pick it up on Monday. Each step
# is something that has to exist in Jira before that is true.
class NextPresenter
  READY_STATUSES = %w[Committed Implementation].freeze
  TOTAL_STEPS = 4

  Delivery = Struct.new(:jira_key, :issue_type, :epic, :ticket_count, keyword_init: true) do
    def tracked_epic? = epic.present?
  end

  # One readiness step as the column shows it: :done, :current (the first one
  # not met, where the work is) or :todo (waiting behind it).
  Step = Struct.new(:label, :state, :detail, :jira_key, keyword_init: true)

  Row = Struct.new(:idea, :deliveries, :steps, :blocker, :checklist, keyword_init: true) do
    def ready? = blocker.nil?
    def total_steps = TOTAL_STEPS
    def steps_met = checklist.count { |step| step.state == :done }
  end

  def self.build
    ideas = DiscoveryIdea.next_up.ranked.includes(:idea_deliveries).to_a
    keys  = ideas.flat_map(&:delivery_keys).uniq
    epics = Epic.active.where(jira_key: keys).index_by(&:jira_key)
    counts = Issue.active.where(epic_id: epics.values.map(&:id)).group(:epic_id).count

    new(ideas: ideas, epics: epics, ticket_counts: counts)
  end

  def initialize(ideas:, epics: {}, ticket_counts: {})
    @ideas = ideas
    @epics = epics
    @ticket_counts = ticket_counts
  end

  def rows
    @rows ||= @ideas.map { |idea| build_row(idea) }
  end

  def ready_count = rows.count(&:ready?)

  # Roadmap items with nothing in Jira behind them at all -- the ones that
  # cannot be started because there is nowhere to put the work.
  def unlinked_count = rows.count { |row| row.deliveries.empty? }

  private

  def build_row(idea)
    deliveries = idea.idea_deliveries.map { |d| build_delivery(d) }
    steps, blocker = score(idea, deliveries)
    Row.new(idea: idea, deliveries: deliveries, steps: steps, blocker: blocker,
            checklist: checklist(idea, deliveries))
  end

  # The same four steps as the score, but each judged on its own, so an item
  # already Committed in the roadmap shows that even while it still waits for
  # a delivery epic. The first step not met is where the work is.
  def checklist(idea, deliveries)
    tracked = deliveries.select(&:tracked_epic?)
    tickets = tracked.sum(&:ticket_count)
    epic_key = tracked.first&.jira_key || deliveries.first&.jira_key
    status = idea.incubator_status.presence
    rows = [
      [ "Delivery ticket", deliveries.any?, deliveries.map(&:jira_key).to_sentence,
        "Link a delivery epic to #{idea.jira_key} in Product Discovery", idea.jira_key ],
      [ "Epic on the board", tracked.any?, tracked.map(&:jira_key).to_sentence,
        not_on_board_hint(deliveries), epic_key ],
      [ "Tickets under the epic", tickets.positive?, "#{tickets} #{'ticket'.pluralize(tickets)}",
        "Break #{epic_key || 'the epic'} down into stories and tasks", epic_key ],
      [ "Committed", READY_STATUSES.include?(status), status,
        "Still #{status || 'not staged'}, move it to Committed", idea.jira_key ]
    ]
    current = rows.index { |row| !row[1] }
    rows.each_with_index.map do |(label, met, done_detail, todo_detail, key), i|
      state = if met then :done elsif i == current then :current else :todo end
      Step.new(label: label, state: state, detail: met ? done_detail : todo_detail, jira_key: key)
    end
  end

  def not_on_board_hint(deliveries)
    return "Needs a delivery epic with the Priority label" if deliveries.empty?

    reason = untracked_blocker(deliveries)
    reason.end_with?("not on the board") ? "#{reason}. Add the Priority label" : reason
  end

  def build_delivery(delivery)
    epic = @epics[delivery.jira_key]
    Delivery.new(
      jira_key: delivery.jira_key,
      issue_type: delivery.issue_type,
      epic: epic,
      ticket_count: epic ? @ticket_counts.fetch(epic.id, 0) : 0
    )
  end

  # There is a delivery ticket, but nothing we could break work down under:
  # either it is the wrong issue type, or it is an epic the board does not carry.
  def untracked_blocker(deliveries)
    epics, others = deliveries.partition { |d| d.issue_type.to_s.casecmp?("epic") }

    if others.any?
      types = others.map { |d| d.issue_type.presence || "ticket" }.uniq.to_sentence
      "Delivered by a #{types}, not an epic"
    else
      verb = epics.one? ? "is" : "are"
      "#{epics.map(&:jira_key).to_sentence} #{verb} not on the board"
    end
  end

  def score(idea, deliveries)
    return [ 0, "No delivery ticket" ] if deliveries.empty?

    tracked = deliveries.select(&:tracked_epic?)
    return [ 1, untracked_blocker(deliveries) ] if tracked.empty?

    return [ 2, "Epic has no tickets yet" ] if tracked.sum(&:ticket_count).zero?
    return [ 3, "Still #{idea.incubator_status}" ] unless READY_STATUSES.include?(idea.incubator_status)

    [ TOTAL_STEPS, nil ]
  end
end
