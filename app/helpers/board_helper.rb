module BoardHelper
  DISPLAY_STATES = [
    { id: "new",         label: "To Do",       short: "To Do",  color: "#94a3b8", tint: "#f1f5f9", deep: "#475569" },
    { id: "in_progress", label: "In Progress", short: "Impl",   color: "#3b82f6", tint: "#eff6ff", deep: "#1d4ed8" },
    { id: "review",      label: "In Review",   short: "Review", color: "#8b5cf6", tint: "#f5f3ff", deep: "#6d28d9" },
    { id: "done",        label: "Done",        short: "Done",   color: "#22c55e", tint: "#f0fdf4", deep: "#15803d" }
  ].freeze

  STATE_BY_ID = DISPLAY_STATES.index_by { |s| s[:id] }.freeze

  STATE_FALLBACK_PALETTE = [
    { color: "#ef4444", tint: "#fef2f2", deep: "#b91c1c" },
    { color: "#f97316", tint: "#fff7ed", deep: "#c2410c" },
    { color: "#eab308", tint: "#fefce8", deep: "#a16207" },
    { color: "#84cc16", tint: "#f7fee7", deep: "#4d7c0f" },
    { color: "#14b8a6", tint: "#f0fdfa", deep: "#0f766e" },
    { color: "#06b6d4", tint: "#ecfeff", deep: "#0e7490" },
    { color: "#a855f7", tint: "#faf5ff", deep: "#7e22ce" },
    { color: "#ec4899", tint: "#fdf2f8", deep: "#be185d" }
  ].freeze

  TYPE_STYLE = {
    "story" => { color: "#16a34a", shape: :square },
    "task"  => { color: "#2563eb", shape: :square },
    "bug"   => { color: "#dc2626", shape: :circle },
    "spike" => { color: "#7c3aed", shape: :square },
    "epic"  => { color: "#a855f7", shape: :square }
  }.freeze

  PRIORITY_LABEL = {
    1 => "Highest", 2 => "High", 3 => "Medium", 4 => "Low", 5 => "Lowest"
  }.freeze
  PRIORITY_COLOR = {
    1 => "#dc2626", 2 => "#ea580c", 3 => "#d97706", 4 => "#2563eb", 5 => "#64748b"
  }.freeze

  STALENESS_STYLE = {
    fresh:    { bg: "#eef2f5", fg: "#64748b", dot: "#cbd5e1", border: "#e7e9ee", paper: "#ffffff" },
    somewhat: { bg: "#fef0e7", fg: "#c2410c", dot: "#f97316", border: "#f3c98a", paper: "#fff7e6" },
    really:   { bg: "#fde7e7", fg: "#b91c1c", dot: "#ef4444", border: "#f0a0a0", paper: "#fff0ea" }
  }.freeze

  AVATAR_PALETTE = %w[#6366f1 #0d9488 #e11d48 #ea580c #8b5cf6 #0284c7 #16a34a #b45309 #c026d3 #475569].freeze

  def state_meta(display_status)
    STATE_BY_ID[display_status] || begin
      id = display_status.to_s
      swatch = BoardHelper.fallback_swatch_for(id)
      label = id.titleize
      { id: id, label: label, short: label, **swatch }
    end
  end

  def self.fallback_swatch_for(id)
    table = swatch_table
    table[id] || STATE_FALLBACK_PALETTE[(table.size + id.bytes.sum) % STATE_FALLBACK_PALETTE.size]
  end

  def self.swatch_table
    cfg_values =
      if defined?(KORKBAN_CONFIG) && KORKBAN_CONFIG.board.status_map
        KORKBAN_CONFIG.board.status_map.values.uniq
      else
        []
      end
    if @swatch_table_key != cfg_values
      @swatch_table_key = cfg_values
      known = STATE_BY_ID.keys
      @swatch_table = (cfg_values - known).each_with_index.to_h do |sid, i|
        [ sid, STATE_FALLBACK_PALETTE[i % STATE_FALLBACK_PALETTE.size] ]
      end
    end
    @swatch_table
  end

  def type_meta(issue_type)
    key = issue_type.to_s.downcase
    TYPE_STYLE[key] || { color: "#64748b", shape: :square }
  end

  def normalized_type(issue_type)
    issue_type.to_s.downcase
  end

  def priority_label(p)
    PRIORITY_LABEL[p&.to_i] || "Medium"
  end

  def priority_color(p)
    PRIORITY_COLOR[p&.to_i] || "#d97706"
  end

  def staleness_meta(bucket)
    STALENESS_STYLE[bucket&.to_sym] || STALENESS_STYLE[:fresh]
  end

  def staleness_label(bucket)
    case bucket&.to_sym
    when :somewhat then "stale"
    when :really then "critical"
    else "fresh"
    end
  end

  def days_in_state(presenter)
    return nil unless presenter.transitioned_at
    ((Time.current - presenter.transitioned_at) / 1.day).to_i
  end

  def avatar_for(username)
    name = username.to_s.strip
    if name.empty?
      { initials: "—", color: "#94a3b8", name: "Unassigned" }
    else
      parts = name.split(/[._\s-]+/).reject(&:empty?)
      initials = parts.first(2).map { |p| p[0].to_s.upcase }.join
      initials = name[0, 2].upcase if initials.empty?
      idx = name.bytes.sum % AVATAR_PALETTE.size
      { initials: initials, color: AVATAR_PALETTE[idx], name: name }
    end
  end

  def type_icon_svg(issue_type, size: 14)
    meta = type_meta(issue_type)
    radius = meta[:shape] == :circle ? 7 : 4
    inner = case normalized_type(issue_type)
    when "story"
              '<path d="M5 4.2h6v7.6l-3-2.2-3 2.2z" fill="#fff"/>'
    when "task"
              '<path d="M4.6 8.2l2 2 4-4.4" stroke="#fff" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>'
    when "bug"
              '<circle cx="8" cy="8" r="2.4" fill="#fff"/>'
    when "spike"
              '<path d="M8.4 4l-3 4.4h2.2l-1 3.6 3.2-4.6H7.6z" fill="#fff"/>'
    when "epic"
              '<path d="M5 5h6v6H5z" fill="#fff"/>'
    else
              ""
    end
    raw <<~SVG.html_safe
      <svg width="#{size}" height="#{size}" viewBox="0 0 16 16" style="display:block" aria-hidden="true">
        <rect x="1" y="1" width="14" height="14" rx="#{radius}" fill="#{meta[:color]}"/>
        #{inner}
      </svg>
    SVG
  end

  def priority_flag_svg(priority, size: 13)
    p = priority&.to_i
    return "".html_safe if p.nil?
    color = priority_color(p)
    chev = ->(y, dir) {
      y1 = y + (dir > 0 ? 3 : 0)
      y2 = y + (dir > 0 ? 0 : 3)
      %(<path d="M3 #{y1} L7 #{y2} L11 #{y1}" stroke="#{color}" stroke-width="1.7" fill="none" stroke-linecap="round" stroke-linejoin="round"/>)
    }
    inner =
      if p == 3
        %(<line x1="3" y1="5.5" x2="11" y2="5.5" stroke="#{color}" stroke-width="1.7" stroke-linecap="round"/><line x1="3" y1="8.5" x2="11" y2="8.5" stroke="#{color}" stroke-width="1.7" stroke-linecap="round"/>)
      elsif p <= 2
        chev.call(3.5, 1) + (p == 1 ? chev.call(7, 1) : "")
      else
        chev.call(3.5, -1) + (p == 5 ? chev.call(7, -1) : "")
      end
    raw <<~SVG.html_safe
      <svg width="#{size}" height="#{size}" viewBox="0 0 14 14" style="display:block" aria-hidden="true">#{inner}</svg>
    SVG
  end

  def ordered_display_states
    configured =
      if defined?(KORKBAN_CONFIG) && KORKBAN_CONFIG.board.status_map
        KORKBAN_CONFIG.board.status_map.values.uniq
      else
        DISPLAY_STATES.map { |s| s[:id] }
      end
    configured.map { |id| state_meta(id) }
  end

  def state_step_index(display_status)
    ordered_display_states.index { |s| s[:id] == display_status } || 0
  end

  def state_total_steps
    ordered_display_states.size - 1
  end
end
