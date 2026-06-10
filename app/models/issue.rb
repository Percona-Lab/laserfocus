class Issue < ApplicationRecord
  belongs_to :epic, optional: true

  scope :active, -> { where(removed_at: nil) }
  scope :orphan, -> { where(epic_id: nil) }

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
end
