# Compares three statements about the same work: what the roadmap committed to
# ("Now" in Jira Product Discovery), what the epic's own status claims, and what
# the tickets are actually doing. Silence means all three agree.
class AlignmentCalculator
  Finding = Struct.new(:kind, :severity, :key, :headline, :detail, keyword_init: true)

  SEVERITY_ORDER = { high: 0, medium: 1, low: 2 }.freeze

  def initialize(columns:, now_ideas:)
    @columns = columns
    @now_ideas = now_ideas
  end

  def configured? = @now_ideas.present?

  def now_total = @now_ideas.size

  def now_on_board
    @now_on_board ||= @now_ideas.count { |idea| (idea.delivery_keys & column_keys).any? }
  end

  def needs_attention = now_total - now_on_board

  def aligned? = needs_attention.zero? && findings.empty?

  def findings
    @findings ||= (idea_findings + column_findings)
      .sort_by { |f| [ SEVERITY_ORDER.fetch(f.severity, 9), f.key.to_s ] }
  end

  private

  def column_keys
    @column_keys ||= @columns.map { |c| c.epic.jira_key }
  end

  def columns_by_key
    @columns_by_key ||= @columns.index_by { |c| c.epic.jira_key }
  end

  def idea_findings
    @now_ideas.flat_map do |idea|
      deliveries = idea.idea_deliveries
      on_board = deliveries.map(&:jira_key) & column_keys

      if deliveries.empty?
        [ Finding.new(kind: :no_delivery, severity: :high, key: idea.jira_key,
                      headline: "No delivery ticket",
                      detail: "#{idea.summary} is committed to Now with nothing in Jira to point at.") ]
      elsif on_board.empty?
        [ Finding.new(kind: :off_board, severity: :high, key: idea.jira_key,
                      headline: "Not on the board",
                      detail: "#{idea.summary} delivers through " \
                              "#{deliveries.map(&:jira_key).join(', ')}, which the board does not show " \
                              "as a column.") ]
      else
        on_board.filter_map do |key|
          column = columns_by_key[key]
          next if column.nil? || column.middle_count.positive?

          Finding.new(kind: :not_started, severity: :high, key: key,
                      headline: "Committed, nothing in flight",
                      detail: "#{idea.jira_key} sits in Now, but no #{key} ticket is in " \
                              "progress or review right now (#{tally(column)}).")
        end
      end
    end
  end

  def column_findings
    @columns.filter_map do |column|
      epic = column.epic
      next if column.lane == :ongoing

      if column.lane == :focus && column.roadmap_idea.nil?
        Finding.new(kind: :unbacked, severity: :low, key: epic.jira_key,
                    headline: "No roadmap item",
                    detail: "#{epic.name} is being worked on with nothing in the roadmap behind it.")
      elsif epic.respond_to?(:in_progress?) && epic.in_progress? && column.middle_count.zero? && column.total_count.positive?
        Finding.new(kind: :status_drift, severity: :medium, key: epic.jira_key,
                    headline: "In Progress, nothing in flight",
                    detail: "#{epic.name} is marked In Progress, but no ticket is in progress " \
                            "or review right now (#{tally(column)}).")
      end
    end
  end

  # What the column actually holds, so a finding reports the snapshot instead of
  # implying the work never started. Finished tickets are the usual reason a
  # column reads as idle without being untouched.
  def tally(column)
    parts = []
    parts << "#{column.done_count} done" if column.done_count.positive?
    parts << "#{column.new_count} waiting" if column.new_count.positive?
    parts.empty? ? "no tickets at all" : parts.join(", ")
  end
end
