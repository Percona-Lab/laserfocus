# One idea from the Jira Product Discovery roadmap project (PGR). The idea's own
# workflow status carries no information -- every idea sits in "Ideation" -- so
# the horizon comes from the roadmap select field and readiness from the
# incubator status field.
class DiscoveryIdea < ApplicationRecord
  HORIZONS = %w[now next].freeze

  has_many :idea_deliveries, dependent: :destroy

  scope :active,  -> { where(removed_at: nil) }
  scope :now,     -> { active.where(horizon: "now") }
  scope :next_up, -> { active.where(horizon: "next") }
  scope :ranked,  -> { order(Arel.sql("rank IS NULL, rank ASC, jira_key ASC")) }

  def delivery_keys
    idea_deliveries.map(&:jira_key)
  end
end
