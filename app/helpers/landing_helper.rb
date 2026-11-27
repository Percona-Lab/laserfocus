module LandingHelper
  # Roadmap-line notices that come from landing quarters and can be snoozed.
  LANDING_FINDING_KINDS = %i[late at_risk no_time_id codename_mismatch].freeze
  LANE_COLORS = %w[#6366f1 #0ea5e9 #d97706 #e11d48 #8b5cf6 #0d9488 #ea580c #c026d3 #10b981 #64748b].freeze

  # A colour per quarter, stable across views.
  def landing_color(quarter)
    return "#0d9488" if quarter.ongoing?
    LANE_COLORS[(quarter.year * 4 + quarter.quarter) % LANE_COLORS.size]
  end

  # "Q1 ’27 · on track ↷2", or the amber "⚠ Time-ID not set". A snoozed
  # warning keeps its text but fades, with a moon.
  def landing_tag(assessment, snooze: nil)
    classes = [ "lq-tag", "lq-s-#{assessment.tone}", ("lq-snoozed" if snooze) ].compact.join(" ")
    title = landing_title(assessment)
    title += "\nSnoozed #{snooze_summary(snooze)}" if snooze
    if assessment.quarter.nil?
      return content_tag(:span, class: classes, title: title) do
        safe_join([ (snooze_icon_svg(size: 9) if snooze), assessment.state == :not_set ? "⚠ Time-ID not set" : assessment.label ].compact)
      end
    end

    content_tag(:span, class: classes, title: title) do
      safe_join([
        (snooze_icon_svg(size: 9) if snooze),
        content_tag(:span, assessment.quarter.letter, class: "lq-mono"),
        "#{assessment.quarter.short_label} · #{assessment.label}",
        (content_tag(:span, " ↷#{assessment.slips.size if assessment.slips.size > 1}", class: "lq-slip") if assessment.slips.any?)
      ].compact)
    end
  end

  # Right-click data for snoozing a roadmap idea's landing warnings, read by
  # snooze_controller.js like a stale card's.
  def landing_snooze_data(key, snooze, warning)
    data = {
      action: "contextmenu->snooze#open", snooze_key: key, staleness: snooze ? "snoozed" : "stale",
      snooze_title: "Snooze roadmap warning", snooze_sub_text: "#{key}: #{warning}",
      snooze_ends: "the warning changes, for example at risk turns late or the Time-ID changes"
    }
    return data unless snooze

    data.merge(
      snoozed_by: snooze.snoozed_by, snoozed_until: snooze_until_label(snooze),
      snooze_days_left: snooze.days_left.to_s, snooze_reason: snooze.reason.to_s,
      snooze_info_note: "The warning comes back when the snooze runs out, or sooner if it changes."
    )
  end

  # Plain-text hover explanation for a landing tag.
  def landing_title(a)
    lines = []
    if a.quarter
      lines << [ a.quarter.codename, a.quarter.period_label, "Time-ID #{a.quarter.id}" ].compact.join(" · ")
      status = a.label.capitalize
      status += " · #{a.days_left} days left in the quarter" if !a.landed? && !a.quarter.ongoing? && a.days_left.to_i >= 0
      lines << status
    end
    lines << a.explanation
    if a.total.positive?
      lines << "#{a.counts[:done]} done · #{a.counts[:in_progress]} in progress · #{a.counts[:todo]} to do"
    end
    if a.slips.any? && a.baseline
      lines << "↷ Slipped #{a.slips.size}× since it was first targeted for #{a.baseline.short_label}"
    end
    lines << "↶ Pulled in #{a.pulls.size}×" if a.pulls.any?
    lines << "⚠ #{a.mismatch}. The Time-ID wins." if a.mismatch && a.quarter
    lines.uniq.join("\n")
  end

  # Days-left counter next to a column's landing tag.
  def landing_days(a)
    return nil if a.quarter.nil? || a.quarter.ongoing? || a.landed?
    days = a.days_left
    tone = days.negative? ? "bad" : days < 30 ? "warn" : nil
    content_tag(:span, days.negative? ? "#{-days}d over" : "#{days}d left", class: [ "lq-days", tone ].compact.join(" "))
  end

  def landing_lane_label(lane)
    case lane
    when LandingQuarter then [ lane.short_label, lane.codename ].compact.join(" · ")
    when :not_set then "⚠ Time-ID not set"
    when :no_idea then "No roadmap item"
    when :ongoing then "Ongoing"
    end
  end
end
