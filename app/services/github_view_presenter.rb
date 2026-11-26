# What the Reviews and Issues views share: who is who (the team versus
# everyone else, the signed-in viewer), the People filter's counts, the
# per-repo counts and the staleness clock. The including presenter provides
# `cards`, each with an `item` (a ReviewPullRequest or a GithubIssue) that
# answers author, replied_logins, asked_logins, participant_logins and no_reply?.
module GithubViewPresenter
  attr_reader :people

  def stale_count = cards.count(&:stale?)
  def snoozed_count = cards.count(&:snoozed?)
  def decision_count = cards.count(&:decision?)
  def community_count = cards.count { |c| c.item.community? }
  def no_reply_count = cards.count { |c| c.item.no_reply? }

  # [repo, count] for the Repo filter, every watched repo. An excluded repo's
  # count is what it would show, so the viewer sees what they leave out.
  def repos
    counts = cards.group_by { |c| c.repo.downcase }.transform_values(&:size)
    @config.repos.map { |r| [ r, counts.fetch(r.downcase) { hidden_counts.fetch(r.downcase, 0) } ] }
  end

  # The repos the viewer took out of their view, lowercased.
  def excluded_repos = @excluded
  def excluded?(repo) = @excluded.include?(repo.to_s.downcase)

  # Everyone who wrote, replied to or is asked onto one of the items, for the
  # People filter: the team first, then everyone else, by display name.
  def logins
    @logins ||= cards.flat_map { |c| [ c.author, *c.item.participant_logins ] }.compact
                     .reject { |l| l.start_with?("@") }.uniq(&:downcase)
  end

  def team_logins = logins.select { |l| @people.team?(l) }.sort_by { |l| @people.display(l).downcase }
  def outside_logins = logins.reject { |l| @people.team?(l) }.sort_by { |l| @people.display(l).downcase }
  def unmatched_members = @people.unmatched_members(logins)

  # How many items a login wrote, replied to, and is asked onto.
  def involvement(login)
    items = cards.map(&:item)
    {
      wrote: items.count { |i| i.author.to_s.casecmp?(login) },
      replied: items.count { |i| i.replied_logins.any? { |l| l.casecmp?(login) } },
      asked: items.count { |i| i.asked_logins.any? { |l| l.casecmp?(login) } }
    }
  end

  # The viewer's GitHub login, so "Mine" matches exactly what ticking their
  # own name under People does. Nil until they show up on an open item.
  def viewer_login
    return @viewer_login if defined?(@viewer_login)
    @viewer_login = logins.find { |l| @people.me?(l) }&.downcase
  end

  def viewer? = @people.viewer?

  # Whether "Mine" and "Needs me" can work: the viewer has a github: override,
  # or one of their names matched someone on the open items.
  def viewer_linked? = viewer_login.present? || @people.viewer_github?

  # Why "Mine" is off, so the viewer can fix it rather than see an empty view.
  def viewer_hint
    return "Sign in with a Google account that has a name, or add yourself to board.users" unless viewer?
    tried = [ @viewer[:google_name] && "the name “#{@viewer[:google_name]}”", @viewer[:email] ].compact.join(" or ")
    "Nobody on the open #{copy[:nouns]} could be linked to you (tried #{tried.presence || "your name"}). " \
      "If you are on one, add github: <your login> to your entry in board.users."
  end

  private

  # The items to show, and the ones the viewer excluded by repo.
  def split_excluded(items, excluded)
    @excluded = excluded.to_set { |r| r.to_s.downcase }
    items.partition { |i| !@excluded.include?(i.repo.downcase) }
  end

  def hidden_counts
    @hidden_counts ||= @hidden.group_by { |i| i.repo.downcase }.transform_values(&:size)
  end

  # Counts with the staleness lead, like days_in_state on the board, so an item
  # looked at during standup is flagged again by the same standup days later.
  def whole_days(since)
    return 0 unless since
    [ ((@now - since + @lead) / 1.day).to_i, 0 ].max
  end

  def bucket_for(days, somewhat, really)
    days >= really ? :really : days >= somewhat ? :somewhat : :fresh
  end
end
