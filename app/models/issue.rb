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
end
