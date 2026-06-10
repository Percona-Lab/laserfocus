class Issue < ApplicationRecord
  belongs_to :epic, optional: true

  scope :active, -> { where(removed_at: nil) }
  scope :orphan, -> { where(epic_id: nil) }
end
