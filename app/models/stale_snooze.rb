# A team member's "yes, we know" on a stale ticket. It holds for the status the
# ticket was in when it was snoozed, so a ticket that moves on and goes stale
# again is highlighted again.
class StaleSnooze < ApplicationRecord
  REASON_LIMIT = 200

  validates :jira_key, :jira_status, :snoozed_until, :snoozed_by, presence: true
  validates :jira_key, uniqueness: true
  validates :reason, length: { maximum: REASON_LIMIT }

  scope :running, ->(now = Time.current) { where("snoozed_until > ?", now) }

  def applies_to?(issue, now: Time.current)
    snoozed_until > now && issue.jira_key == jira_key && issue.jira_status == jira_status
  end

  def days_left(now: Time.current)
    ((snoozed_until - now) / 1.day).ceil
  end

  # Drops snoozes that can no longer apply: run out, the ticket changed status,
  # or the ticket left the board. PR and issue snoozes (see GithubKeyed) share
  # the table and are pruned by ReviewSync and IssueSync instead. Snoozes on a
  # roadmap idea's landing warnings simply stop applying once the warnings
  # change, and run out like the rest.
  def self.prune!(now: Time.current)
    where(snoozed_until: ..now).delete_all
    statuses = Issue.active.where(jira_key: select(:jira_key)).pluck(:jira_key, :jira_status).to_h
    ideas = DiscoveryIdea.where(jira_key: select(:jira_key)).pluck(:jira_key).to_set
    dead = all.reject do |s|
      GithubKeyed.key?(s.jira_key) || ideas.include?(s.jira_key) || statuses[s.jira_key] == s.jira_status
    end.map(&:id)
    where(id: dead).delete_all if dead.any?
  end
end
