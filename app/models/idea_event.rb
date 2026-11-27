# One change to a discovery idea's Time-ID, Codename or roadmap horizon, as the
# Jira changelog recorded it. Kept so a slip stays visible after the field has
# moved on, and so /roadmap can show who changed the plan and when.
class IdeaEvent < ApplicationRecord
  FIELDS = %w[time_id codename horizon].freeze

  validates :jira_key, :field, :occurred_at, presence: true
  validates :field, inclusion: { in: FIELDS }

  scope :chronological, -> { order(:occurred_at, :id) }
end
