class Epic < ApplicationRecord
  has_many :issues, dependent: :destroy

  scope :active,  -> { where(removed_at: nil) }
  scope :ordered, -> { order(priority: :asc, name: :asc) }

  def assignee_name
    assignee = (raw_fields || {})["assignee"]
    return nil unless assignee.is_a?(Hash)
    assignee["displayName"] || assignee["name"]
  end
end
