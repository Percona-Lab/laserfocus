class Epic < ApplicationRecord
  has_many :issues, dependent: :destroy

  scope :active,  -> { where(removed_at: nil) }
  scope :ordered, -> { order(created_at: :asc, id: :asc) }

  # Jira's own coarse bucket for the epic workflow: "new", "indeterminate"
  # (in progress) or "done". Survives status renames, which the raw name does not.
  def status_category
    (raw_fields || {}).dig("status", "statusCategory", "key").presence
  end

  def in_progress?
    status_category == "indeterminate"
  end

  def labels
    Array((raw_fields || {})["labels"]).filter_map { |l| l.to_s.presence }
  end

  def ongoing?(label)
    label.present? && labels.include?(label)
  end

  def assignee_name
    assignee = (raw_fields || {})["assignee"]
    return nil unless assignee.is_a?(Hash)
    assignee["displayName"] || assignee["name"]
  end
end
