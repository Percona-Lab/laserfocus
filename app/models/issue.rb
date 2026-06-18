class Issue < ApplicationRecord
  belongs_to :epic, optional: true

  scope :active, -> { where(removed_at: nil) }
  scope :orphan, -> { where(epic_id: nil) }

  def pull_requests
    val = read_attribute(:pull_requests)
    val.is_a?(Array) ? val.select { |p| p.is_a?(Hash) } : []
  end

  def description
    raw = (raw_fields || {})["description"]
    return nil if raw.blank?
    raw.is_a?(String) ? raw.strip.presence : adf_to_text(raw)
  end

  def description_html
    raw = (raw_fields || {})["description"]
    return nil if raw.blank?
    raw.is_a?(Hash) ? adf_to_html(raw) : jira_wiki_to_html(raw.to_s)
  end

  def parent_jira_key
    fields = raw_fields || {}
    parent = fields["parent"] || fields[:parent]
    return nil unless parent.respond_to?(:[])

    parent["key"] || parent[:key]
  end

  def labels
    fields = raw_fields || {}
    Array(fields["labels"] || fields[:labels]).filter_map { |label| label.to_s.presence }
  end

  def components
    fields = raw_fields || {}
    Array(fields["components"] || fields[:components]).filter_map do |component|
      if component.is_a?(Hash)
        (component["name"] || component[:name]).to_s.presence
      else
        component.to_s.presence
      end
    end
  end

  private

  def adf_to_text(node)
    return "" unless node.is_a?(Hash)
    paragraphs = []
    collect_adf_paragraphs(node, paragraphs)
    paragraphs.reject(&:empty?).join("\n\n").strip.presence
  end

  def collect_adf_paragraphs(node, paragraphs)
    type = node["type"]
    children = Array(node["content"])

    if %w[paragraph heading].include?(type)
      text = children.filter_map { |c| c["text"] if c["type"] == "text" }.join
      paragraphs << text
    elsif type == "text"
      paragraphs << node["text"].to_s
    else
      children.each { |c| collect_adf_paragraphs(c, paragraphs) }
    end
  end

  def jira_wiki_to_html(text)
    lines = text.strip.split("\n")
    out = +""
    i = 0
    while i < lines.size
      line = lines[i]
      if line =~ /\Ah([1-6])\.\s*(.*)/m
        out << "<p><strong>#{inline_wiki($2)}</strong></p>"
        i += 1
      elsif line =~ /\A\*\s+(.*)/
        out << "<ul>"
        while i < lines.size && lines[i] =~ /\A\*\s+(.*)/
          out << "<li>#{inline_wiki($1)}</li>"
          i += 1
        end
        out << "</ul>"
      elsif line =~ /\A#\s+(.*)/
        out << "<ol>"
        while i < lines.size && lines[i] =~ /\A#\s+(.*)/
          out << "<li>#{inline_wiki($1)}</li>"
          i += 1
        end
        out << "</ol>"
      elsif line.strip.empty?
        i += 1
      else
        para = []
        while i < lines.size && lines[i].strip.present? && lines[i] !~ /\Ah[1-6]\.|\A[*#]\s/
          para << inline_wiki(lines[i])
          i += 1
        end
        out << "<p>#{para.join("<br>")}</p>" if para.any?
      end
    end
    out
  rescue StandardError
    "<p>#{CGI.escapeHTML(text.strip)}</p>"
  end

  def inline_wiki(text)
    out = +""
    rest = text.dup
    patterns = [
      [/\[([^\]|]*)\|([^\]|]+)\|[^\]]+\]/, :jira_smart],  # [text|url|type]
      [/\[([^\]|]+)\|([^\]|]+)\]/,          :jira_link],   # [text|url]
      [/\[([^\]]+)\]/,                       :jira_bare],   # [url]
      [/\{\{([^}]+)\}\}/,                    :code],
      [/(?<![a-zA-Z0-9])\*([^*\n]+)\*(?![a-zA-Z0-9])/, :bold],
      [/(?<![a-zA-Z0-9])_([^_\n]+)_(?![a-zA-Z0-9])/,   :italic],
      [/https?:\/\/[^\s<>"|]+/,              :bare_url],
    ]
    until rest.empty?
      earliest = nil
      patterns.each do |pat, type|
        m = rest.match(pat)
        next unless m
        earliest = [m.begin(0), type, m] if earliest.nil? || m.begin(0) < earliest[0]
      end
      unless earliest
        out << CGI.escapeHTML(rest)
        break
      end
      pos, type, m = earliest
      out << CGI.escapeHTML(rest[0, pos]) if pos > 0
      rest = rest[(pos + m[0].length)..]
      case type
      when :jira_smart
        label, url = m[1].presence || m[2], m[2]
        if url.match?(/\Ahttps?:\/\//i)
          out << %(<a href="#{CGI.escapeHTML(url)}" target="_blank" rel="noreferrer">#{CGI.escapeHTML(label)}</a>)
        else
          out << CGI.escapeHTML(label)
        end
      when :jira_link
        label, url = m[1], m[2]
        if url.match?(/\Ahttps?:\/\//i)
          out << %(<a href="#{CGI.escapeHTML(url)}" target="_blank" rel="noreferrer">#{CGI.escapeHTML(label)}</a>)
        else
          out << CGI.escapeHTML(label)
        end
      when :jira_bare
        url = m[1]
        if url.match?(/\Ahttps?:\/\//i)
          out << %(<a href="#{CGI.escapeHTML(url)}" target="_blank" rel="noreferrer">#{CGI.escapeHTML(url)}</a>)
        else
          out << CGI.escapeHTML(url)
        end
      when :code
        out << "<code>#{CGI.escapeHTML(m[1])}</code>"
      when :bold
        out << "<strong>#{CGI.escapeHTML(m[1])}</strong>"
      when :italic
        out << "<em>#{CGI.escapeHTML(m[1])}</em>"
      when :bare_url
        url = m[0]
        out << %(<a href="#{CGI.escapeHTML(url)}" target="_blank" rel="noreferrer">#{CGI.escapeHTML(url)}</a>)
      end
    end
    out
  end

  def adf_to_html(node)
    return "" unless node.is_a?(Hash)
    render_adf_node(node)
  rescue StandardError
    ""
  end

  def render_adf_node(node)
    return "" unless node.is_a?(Hash)
    children = Array(node["content"])
    case node["type"]
    when "doc"         then children.map { |c| render_adf_node(c) }.join
    when "paragraph"
      inner = children.map { |c| render_adf_node(c) }.join
      inner.empty? ? "" : "<p>#{inner}</p>"
    when "heading"
      "<p><strong>#{children.map { |c| render_adf_node(c) }.join}</strong></p>"
    when "bulletList"  then "<ul>#{children.map { |c| render_adf_node(c) }.join}</ul>"
    when "orderedList" then "<ol>#{children.map { |c| render_adf_node(c) }.join}</ol>"
    when "listItem"    then "<li>#{children.map { |c| render_adf_node(c) }.join}</li>"
    when "hardBreak"   then "<br>"
    when "text"
      content = CGI.escapeHTML(node["text"].to_s)
      Array(node["marks"]).each do |mark|
        case mark["type"]
        when "strong" then content = "<strong>#{content}</strong>"
        when "em"     then content = "<em>#{content}</em>"
        when "code"   then content = "<code>#{content}</code>"
        when "link"
          href = mark.dig("attrs", "href").to_s
          if href.match?(/\Ahttps?:\/\//i)
            content = %(<a href="#{CGI.escapeHTML(href)}" target="_blank" rel="noreferrer">#{content}</a>)
          end
        end
      end
      content
    else
      children.map { |c| render_adf_node(c) }.join
    end
  end
end
