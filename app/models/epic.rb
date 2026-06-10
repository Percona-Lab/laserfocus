class Epic < ApplicationRecord
  has_many :issues, dependent: :destroy

  scope :active,  -> { where(removed_at: nil) }
  scope :ordered, -> { order(priority: :asc, name: :asc) }
end
