# Judges one discovery idea against its internal landing target: has it
# landed, is it late, at risk, on track, or only planned. The Time-ID alone sets
# the target. Without one the idea has none (:not_set), even when a Codename is
# filled in: nothing here guesses.
class LandingAssessment
  TargetChange = Struct.new(:occurred_at, :from, :to, :kind, :author, keyword_init: true)

  LABELS = {
    landed: "landed", landed_late: "landed late", late: "late", at_risk: "at risk",
    on_track: "on track", planned: "planned", ongoing: "ongoing",
    not_set: "Time-ID not set", dropped: "dropped"
  }.freeze

  # CSS modifier per state (lq-s-*).
  TONES = {
    landed: "landed", landed_late: "landedlate", late: "late", at_risk: "risk",
    on_track: "track", planned: "planned", ongoing: "ongoing",
    not_set: "none", dropped: "none"
  }.freeze

  # Worst first, for sorting within a quarter.
  SEVERITY = { late: 0, at_risk: 1, not_set: 2, on_track: 3, planned: 4, ongoing: 5,
               landed_late: 6, landed: 7, dropped: 8 }.freeze

  # How far progress (done + half of in progress) may trail the share of the
  # quarter that has gone before an idea counts as at risk.
  BEHIND_TOLERANCE = 0.3
  # A target changed this soon after it was first set is a correction, not a
  # slip.
  GRACE_PERIOD = 2.days

  attr_reader :idea, :quarter, :state, :reasons, :today, :target_changes, :baseline,
              :landed_on, :late_by, :now_since, :mismatch, :counts

  def initialize(idea, calendar:, today: Date.current)
    @idea = idea
    @today = today
    @calendar = calendar
    @deliveries = idea.idea_deliveries.to_a
    @events = idea.idea_events.to_a
    @quarter = calendar.quarter(idea.time_id) if idea.time_id
    @reasons = []
    @counts = {
      todo: @deliveries.sum { |d| d.todo_count.to_i },
      in_progress: @deliveries.sum { |d| d.in_progress_count.to_i },
      done: @deliveries.sum { |d| d.done_count.to_i }
    }
    @mismatch = compute_mismatch
    @target_changes = compute_target_changes
    settled = @target_changes.reverse.find { |c| %i[set corrected].include?(c.kind) }
    @baseline = settled ? settled.to : @quarter
    @now_since = @events.find { |e| e.field == "horizon" && e.to_value.to_s.casecmp?("Now") }&.occurred_at
    @landed_on = compute_landed_on
    @state = compute_state
  end

  def label = LABELS.fetch(state)
  def tone = TONES.fetch(state)
  def severity = SEVERITY.fetch(state)
  def deliveries = @deliveries

  def slips = target_changes.select { |c| c.kind == :slip }
  def pulls = target_changes.select { |c| c.kind == :pull }

  def landed? = %i[landed landed_late].include?(state)
  def target? = quarter.present?

  def total = counts.values.sum

  # Done counts fully, in progress half.
  def progress = total.zero? ? 0.0 : (counts[:done] + counts[:in_progress] * 0.5) / total

  # Share of the target quarter already gone, nil outside it.
  def elapsed
    return nil unless quarter && !quarter.ongoing? && quarter.cover?(today)
    (today - quarter.starts_on).to_f / (quarter.ends_on - quarter.starts_on + 1)
  end

  def days_left = quarter && (quarter.ends_on - today).to_i

  # One line saying why the idea is where it is.
  def explanation
    case state
    when :landed then landed_on ? "Landed #{landed_on.strftime('%-d %b %Y')}, inside #{quarter.period_label}." : "Landed inside #{quarter.period_label}."
    when :landed_late then "Landed #{landed_on.strftime('%-d %b %Y')}, #{late_by} days after #{quarter.period_label} ended."
    when :dropped then "Closed without landing (#{idea.incubator_status})."
    when :not_set
      base = idea.time_id ? "Time-ID #{idea.time_id} is not a valid landing quarter." : "Time-ID not set in Discovery, so there is no landing quarter."
      idea.codename.present? && idea.time_id.nil? ? "#{base} The Codename says #{idea.codename}, but LaserFocus doesn't guess from it." : base
    when :ongoing then "Ongoing commitment for #{quarter.year}."
    when :planned then "Planned for #{quarter.period_label}."
    when :on_track then "On track: #{(progress * 100).round}% done with #{((elapsed || 0) * 100).round}% of the quarter gone."
    else reasons.join(" · ")
    end
  end

  private

  # The Codename should be the one the other ideas with this Time-ID carry.
  def compute_mismatch
    expected = @quarter&.codename
    return nil if expected.nil? || idea.codename.blank? || expected == idea.codename
    "Time-ID #{idea.time_id} is #{expected}, but Codename says #{idea.codename}"
  end

  # Changes of target over time, from the Time-ID history when there is one and
  # the Codename history otherwise. A change within the grace period of the
  # first target is a correction, not a slip.
  def compute_target_changes
    time_ids = @events.select { |e| e.field == "time_id" }
    source = if time_ids.any?
      time_ids.map { |e| [ e, quarter_for_id(e.from_value), quarter_for_id(e.to_value) ] }
    else
      @events.select { |e| e.field == "codename" }
             .map { |e| [ e, quarter_for_codename(e.from_value), quarter_for_codename(e.to_value) ] }
    end
    first_set = source.find { |_, _, to| to }&.first&.occurred_at

    source.filter_map do |event, from, to|
      kind = if from.nil? && to then :set
      elsif from && to.nil? then :cleared
      elsif from && to && to > from then :slip
      elsif from && to && to < from then :pull
      end
      next if kind.nil?

      if %i[slip pull].include?(kind) && first_set && event.occurred_at - first_set < GRACE_PERIOD
        kind = :corrected
      end
      TargetChange.new(occurred_at: event.occurred_at, from: from, to: to, kind: kind, author: event.author)
    end
  end

  def quarter_for_id(value)
    value.present? ? @calendar.quarter(value) : nil
  end

  def quarter_for_codename(value) = @calendar.quarter_for_codename(value)

  def compute_landed_on
    resolved = @deliveries.filter_map(&:resolved_at)
    all_done = @deliveries.any? && @deliveries.all? { |d| d.status_category == "done" }
    closed_at = @events.select { |e| e.field == "horizon" && e.to_value.to_s.casecmp?("Closed") }.last&.occurred_at

    at = if idea.succeeded?
      all_done && resolved.any? ? resolved.max : (closed_at || resolved.max)
    elsif !idea.closed? && all_done
      resolved.max
    end
    @landed_without_date = at.nil? && idea.succeeded?
    at&.to_date
  end

  def compute_state
    return :dropped if idea.closed? && !idea.succeeded?

    landed = landed_on.present? || @landed_without_date
    return :not_set if quarter.nil?

    if landed
      return :landed if landed_on.nil? || landed_on <= quarter.ends_on
      @late_by = (landed_on - quarter.ends_on).to_i
      return :landed_late
    end
    if today > quarter.ends_on
      @late_by = (today - quarter.ends_on).to_i
      @reasons << "#{late_by} days past the end of #{quarter.period_label}" unless quarter.ongoing?
      return :late
    end
    return :ongoing if quarter.ongoing?

    # Only the quarter we are in can be at risk; later ones are just planned.
    return :planned unless quarter.cover?(today)

    collect_current_quarter_reasons
    reasons.any? ? :at_risk : :on_track
  end

  def collect_current_quarter_reasons
    @reasons << "Targets this quarter but the roadmap still has it in #{idea.horizon_label}" unless idea.horizon == "now"
    if @deliveries.empty?
      @reasons << "No delivery ticket linked"
    elsif total.zero?
      @reasons << "The delivery ticket has no tickets yet"
    elsif counts[:in_progress].zero? && counts[:done].zero?
      @reasons << "Nothing started"
    elsif progress < elapsed - BEHIND_TOLERANCE
      @reasons << "#{(progress * 100).round}% done with #{(elapsed * 100).round}% of the quarter gone"
    end
  end
end
