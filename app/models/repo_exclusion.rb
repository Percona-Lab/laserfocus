# A repo one viewer has taken out of their own Reviews and Issues views, from
# the right-click menu on the Repo filter. Its PRs and issues are gone for that
# viewer only, red tab counts included; everyone else still sees them.
class RepoExclusion < ApplicationRecord
  validates :user_email, :repo, presence: true
  validates :repo, uniqueness: { scope: :user_email }

  before_validation { self.user_email = user_email.to_s.downcase; self.repo = repo.to_s.downcase }

  # The viewer's excluded repos, lowercased.
  def self.repos_for(email)
    return Set.new if email.blank?
    where(user_email: email.to_s.downcase).pluck(:repo).to_set
  end

  # Every repo the Reviews or Issues view watches, lowercased: the only ones
  # that can be excluded.
  def self.watchable
    [ LASER_FOCUS_CONFIG.reviews, LASER_FOCUS_CONFIG.issues ].compact
      .flat_map(&:repos).map(&:downcase).to_set
  end
end
