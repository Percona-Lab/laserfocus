# The hidden /roadmap page: one card per landing quarter, a timeline of every
# targeted idea, and the log of plan changes (targets set, slips, pull-ins,
# horizon moves, landings).
class RoadmapPresenter
  Card = Struct.new(:quarter, :targeted, :landed, :landed_late, :late, :at_risk, :slipped_out,
                    :current, :past, keyword_init: true) do
    def landed_total = landed + landed_late
    def on_track = targeted - landed_total - late - at_risk
  end
  Group = Struct.new(:quarter, :title, :hint, :rows, :warn, keyword_init: true)
  Mark = Struct.new(:kind, :left, :width, :title, :color, keyword_init: true)
  Band = Struct.new(:quarter_label, :animal, :id, :left, :width, :current, :months, keyword_init: true)
  Change = Struct.new(:at, :assessment, :kind, :text, :author, keyword_init: true)

  RANGES = %w[rolling].freeze
  CHANGE_FILTERS = {
    "all" => nil,
    "targets" => %i[set slip pull cleared corrected landed landed_late],
    "slips" => %i[slip pull cleared corrected],
    "horizon" => %i[up down closed]
  }.freeze
  HORIZON_RANK = { "incubator" => 0, "later" => 1, "next" => 2, "now" => 3, "closed" => 4 }.freeze
  STATE_COLORS = {
    on_track: "#16a34a", at_risk: "#d97706", late: "#dc2626", landed: "#4d7c5f", landed_late: "#a16a35",
    planned: "#3b6fe0", ongoing: "#0d9488", not_set: "#d97706", dropped: "#9ca3af"
  }.freeze

  def self.build(params, today: Date.current, discovery: LASER_FOCUS_CONFIG.discovery)
    board = LandingBoard.build(today: today, discovery: discovery)
    board && new(board, params)
  end

  attr_reader :board, :range, :quarter_filter, :selected_key, :change_filter

  def initialize(board, params = {})
    @board = board
    @range = params[:range].to_s =~ /\A\d{4}\z/ ? params[:range].to_s : "rolling"
    @quarter_filter = params[:quarter].presence&.to_i
    @selected_key = params[:idea].presence
    @change_filter = CHANGE_FILTERS.key?(params[:changes].to_s) ? params[:changes].to_s : "all"
  end

  # Query params for a link that keeps the current filters, with overrides
  # (nil drops one).
  def link_params(**overrides)
    {
      range: (range unless range == "rolling"),
      quarter: quarter_filter,
      idea: selected_key,
      changes: (change_filter unless change_filter == "all")
    }.merge(overrides).compact
  end

  def today = board.today
  def assessments = board.assessments
  def calendar = board.calendar

  def window
    @window ||= if range == "rolling"
      quarter_start = Date.new(today.year, ((today.month - 1) / 3) * 3 + 1, 1)
      start = quarter_start.prev_month(3)
      [ start, start.next_month(15) - 1 ]
    else
      [ Date.new(range.to_i, 1, 1), Date.new(range.to_i, 12, 31) ]
    end
  end

  def range_options
    [ [ "rolling", "Rolling 15 months" ], [ today.year.to_s, today.year.to_s ], [ (today.year + 1).to_s, (today.year + 1).to_s ] ]
  end

  # Position of a day on the timeline, in percent.
  def pct(date)
    first, last = window
    span = (last - first + 1).to_f
    ((date - first) / span * 100).clamp(0, 100).round(3)
  end

  def in_window?(from, to) = to >= window.first && from <= window.last

  def today_pct = in_window?(today, today) ? pct(today) : nil

  def bands
    @bands ||= begin
      list = []
      d = window.first
      while d <= window.last
        q_end = d.next_month(3) - 1
        quarter = calendar.containing(d)
        months = (0..2).map do |m|
          md = d.next_month(m)
          { label: md.strftime("%b"), left: ((pct(md) - pct(d)) / [ pct(q_end + 1) - pct(d), 0.001 ].max * 100).round(2) }
        end
        list << Band.new(quarter_label: "Q#{(d.month - 1) / 3 + 1} ’#{d.year % 100}", animal: quarter&.animal, id: quarter&.id,
                         left: pct(d), width: (pct(q_end + 1) - pct(d)).round(3), current: (d..q_end).cover?(today),
                         months: months)
        d = q_end + 1
      end
      list
    end
  end

  def cards
    @cards ||= begin
      quarters = assessments.reject { |a| a.state == :dropped }.filter_map(&:quarter).uniq
      quarters.select { |q| in_window?(q.starts_on, q.ends_on) || assessments.any? { |a| a.quarter == q } }
              .sort_by(&:id)
              .map { |q| card_for(q) }
    end
  end

  def groups
    @groups ||= begin
      shown = assessments.reject { |a| a.state == :dropped }.select { |a| shown?(a) }
      if quarter_filter
        shown = shown.select { |a| a.quarter&.id == quarter_filter || a.slips.any? { |s| s.from&.id == quarter_filter } }
      end

      list = shown.select(&:quarter).group_by(&:quarter).sort_by { |q, _| q.id }.map do |q, rows|
        Group.new(quarter: q, title: [ q.short_label, q.codename ].compact.join(" · "), rows: sort_rows(rows))
      end
      not_set = shown.select { |a| a.state == :not_set }
      if not_set.any?
        list << Group.new(title: "⚠ Time-ID not set", hint: "No landing quarter; LaserFocus doesn't guess",
                          rows: sort_rows(not_set), warn: true)
      end
      list
    end
  end

  # The marks drawn on one idea's timeline row.
  def marks(a)
    color = STATE_COLORS.fetch(a.state)
    list = []
    a.slips.each do |slip|
      next unless slip.from && in_window?(slip.from.starts_on, slip.from.ends_on)
      list << Mark.new(kind: :ghost, left: pct(slip.from.starts_on), width: span(slip.from),
                       title: "Was #{slip.from.name} until #{slip.occurred_at.to_date.strftime('%-d %b %Y')}")
    end
    if (last = a.slips.last) && a.quarter && last.from
      from = pct(last.from.ends_on + 1)
      list << Mark.new(kind: :arrow, left: from, width: [ pct(a.quarter.starts_on) - from, 0 ].max)
    end
    if a.quarter && in_window?(a.quarter.starts_on, a.quarter.ends_on)
      list << Mark.new(kind: :target, left: pct(a.quarter.starts_on), width: span(a.quarter), color: color,
                       title: "#{a.quarter.name} · #{a.quarter.period_label}")
    end
    if a.now_since
      start = a.now_since.to_date
      finish = a.landed_on || today
      if finish > start && in_window?(start, finish)
        list << Mark.new(kind: :work, left: pct(start), width: (pct(finish) - pct(start)).round(3),
                         color: a.landed? ? "#9fb8a8" : "#94a3b8", title: "In Now since #{start.strftime('%-d %b %Y')}")
      end
    end
    if a.state == :late && a.quarter && !a.quarter.ongoing?
      list << Mark.new(kind: :late, left: pct(a.quarter.ends_on + 1), width: (pct(today) - pct(a.quarter.ends_on + 1)).round(3))
    end
    if a.landed_on && in_window?(a.landed_on, a.landed_on)
      list << Mark.new(kind: :landed, left: pct(a.landed_on), color: color, title: "Landed #{a.landed_on.strftime('%-d %b %Y')}")
    end
    list
  end

  # Where the state chip sits: after the landing, the overdue tail or the target.
  def chip_left(a)
    at = if a.landed_on then a.landed_on
    elsif a.state == :late then today
    elsif a.quarter then a.quarter.ends_on
    end
    return nil if at.nil? || !in_window?(at, at)
    left = pct(at)
    left.between?(0.5, 90) ? left : nil
  end

  def chip_text(a)
    text = a.label
    text += " +#{a.late_by}d" if a.late_by.to_i.positive?
    text += " ↷#{a.slips.size}" if a.slips.any?
    text
  end

  def selected
    @selected ||= selected_key && assessments.find { |a| a.idea.jira_key == selected_key }
  end

  def changes
    @changes ||= begin
      list = []
      assessments.each do |a|
        a.target_changes.each { |c| list << Change.new(at: c.occurred_at, assessment: a, kind: c.kind, text: target_text(c), author: c.author) }
        a.idea.idea_events.each do |e|
          next unless e.field == "horizon" && e.from_value.present? && e.to_value.present?
          kind = if e.to_value.casecmp?("Closed") then :closed
          elsif HORIZON_RANK.fetch(e.to_value.downcase, -1) > HORIZON_RANK.fetch(e.from_value.downcase, -1) then :up
          else :down
          end
          text = kind == :closed ? "Closed (from #{ERB::Util.h(e.from_value)})" : "#{ERB::Util.h(e.from_value)} → <b>#{ERB::Util.h(e.to_value)}</b>"
          list << Change.new(at: e.occurred_at, assessment: a, kind: kind, text: text, author: e.author)
        end
        if a.landed_on && a.quarter
          text = a.state == :landed ? "Landed in #{a.quarter.short_label}, on target" : "Landed #{a.late_by} days after #{a.quarter.short_label} ended"
          list << Change.new(at: a.landed_on.to_time, assessment: a, kind: a.state, text: text)
        end
      end
      kinds = CHANGE_FILTERS[change_filter]
      list.select! { |c| kinds.nil? || kinds.include?(c.kind) }
      list.select! { |c| c.assessment.idea.jira_key == selected_key } if selected_key
      list.sort_by { |c| -c.at.to_f }.first(150)
    end
  end

  def changes_by_day = changes.group_by { |c| c.at.to_date }

  private

  def span(quarter) = (pct(quarter.ends_on + 1) - pct(quarter.starts_on)).round(3)

  def shown?(a)
    return true if a.quarter
    !a.idea.closed? && (%w[now next].include?(a.idea.horizon) || a.idea.codename.present? || a.idea.time_id)
  end

  def sort_rows(rows)
    rows.sort_by do |a|
      [ a.severity, -(a.landed_on&.jd || 0), a.idea.jira_key[/\d+\z/].to_i ]
    end
  end

  def card_for(q)
    group = assessments.select { |a| a.quarter == q && a.state != :dropped }
    Card.new(
      quarter: q,
      targeted: group.size,
      landed: group.count { |a| a.state == :landed },
      landed_late: group.count { |a| a.state == :landed_late },
      late: group.count { |a| a.state == :late },
      at_risk: group.count { |a| a.state == :at_risk },
      slipped_out: assessments.count { |a| a.slips.any? { |s| s.from == q } },
      current: !q.ongoing? && q.cover?(today),
      past: today > q.ends_on
    )
  end

  def target_text(c)
    h = ERB::Util
    case c.kind
    when :set then "Target set to <b>#{c.to.short_label}</b>#{c.to.codename ? " (#{h.h(c.to.codename)})" : ''}"
    when :cleared then "Target cleared (was #{c.from.short_label})"
    when :corrected then "Target corrected <b>#{c.from.short_label} → #{c.to.short_label}</b> right after it was set, so it doesn't count as a slip"
    when :slip then "Slipped <b>#{c.from.short_label} → #{c.to.short_label}</b> (#{h.h(c.from.name)} → #{h.h(c.to.name)})"
    when :pull then "Pulled in <b>#{c.from.short_label} → #{c.to.short_label}</b> (#{h.h(c.from.name)} → #{h.h(c.to.name)})"
    end
  end
end
