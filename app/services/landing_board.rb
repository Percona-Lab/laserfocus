# Landing quarters for one render of the board: an assessment per discovery
# idea, which idea an epic column delivers, and the roadmap line's summary of
# the current quarter with its notices. Absent (nil) when the deployment has no
# Time-ID configured.
class LandingBoard
  Finding = AlignmentCalculator::Finding
  Summary = Struct.new(:quarter, :targeted, :landed, :at_risk, :late, :days_left, keyword_init: true)

  HORIZON_PREFERENCE = { "now" => 0, "next" => 1 }.freeze

  def self.build(today: Date.current, discovery: LASER_FOCUS_CONFIG.discovery)
    return nil unless discovery&.landing?

    ideas = DiscoveryIdea.active.includes(:idea_deliveries, :idea_events).to_a
    new(ideas: ideas, today: today, calendar: LandingCalendar.build(discovery, ideas))
  end

  attr_reader :assessments, :today, :calendar

  def initialize(ideas:, today:, calendar:)
    @today = today
    @calendar = calendar
    @assessments = ideas.map { |idea| LandingAssessment.new(idea, calendar: calendar, today: today) }
  end

  # The idea an epic delivers. An epic can sit behind more than one idea; the
  # one in Now wins, then Next, then any other open one, then a closed one.
  def for_epic(jira_key)
    by_delivery_key[jira_key]
  end

  def current_quarter = calendar.containing(today)

  # The current quarter at a glance, for the ideas `in_view` accepts.
  def summary(in_view: ->(_) { true })
    quarter = current_quarter
    return nil if quarter.nil?

    scoped = assessments.select { |a| in_view.call(a.idea) }
    in_quarter = scoped.select { |a| a.quarter == quarter && a.state != :dropped }
    Summary.new(
      quarter: quarter,
      targeted: in_quarter.size,
      landed: in_quarter.count(&:landed?),
      at_risk: in_quarter.count { |a| a.state == :at_risk },
      late: scoped.count { |a| a.state == :late },
      days_left: (quarter.ends_on - today).to_i
    )
  end

  # Notices for the roadmap line: late and at-risk ideas, and ideas whose
  # target cannot be trusted (no Time-ID, or a Codename that disagrees).
  def findings(in_view: ->(_) { true })
    assessments.select { |a| in_view.call(a.idea) && !a.idea.closed? }.flat_map do |a|
      idea = a.idea
      list = []
      case a.state
      when :late
        detail = if a.quarter.ongoing?
          "Ongoing for #{a.quarter.year}, which is over, and not landed."
        else
          "Targeted #{a.quarter.period_label}#{codename_suffix(a.quarter)}, #{a.late_by} days past the end of the quarter and not landed."
        end
        list << Finding.new(kind: :late, severity: :high, key: idea.jira_key,
                            headline: "#{idea.summary} is late", detail: detail)
      when :at_risk
        list << Finding.new(kind: :at_risk, severity: :medium, key: idea.jira_key,
                            headline: "#{idea.summary} is at risk for #{a.quarter.short_label}",
                            detail: "#{a.reasons.join(' · ')} · #{a.days_left} days left.")
      when :not_set
        if %w[now next].include?(idea.horizon) || idea.codename.present? || idea.time_id
          list << Finding.new(kind: :no_time_id, severity: :low, key: idea.jira_key,
                              headline: "#{idea.summary}: Time-ID not set", detail: not_set_detail(idea))
        end
      end
      if a.mismatch && a.quarter
        list << Finding.new(kind: :codename_mismatch, severity: :low, key: idea.jira_key,
                            headline: "#{idea.summary}: Time-ID and Codename disagree",
                            detail: "#{a.mismatch}. LaserFocus goes by the Time-ID; fix the Codename in Discovery.")
      end
      list
    end
  end

  private

  def by_delivery_key
    @by_delivery_key ||= assessments
      .sort_by { |a| [ a.idea.closed? ? 3 : HORIZON_PREFERENCE.fetch(a.idea.horizon, 2), a.idea.jira_key ] }
      .each_with_object({}) do |a, map|
        a.idea.idea_deliveries.each { |d| map[d.jira_key] ||= a }
      end
  end

  def codename_suffix(quarter) = quarter.codename.present? ? " (#{quarter.codename})" : ""

  def not_set_detail(idea)
    if idea.time_id
      "Time-ID #{idea.time_id} is not a valid landing quarter. Fix it in Discovery."
    elsif idea.codename.present?
      "In #{idea.horizon_label} with Codename #{idea.codename}, but no Time-ID. " \
        "LaserFocus doesn't guess from the Codename; set the Time-ID."
    else
      "In #{idea.horizon_label} without a Time-ID. Set one so standup can see when it should land."
    end
  end
end
