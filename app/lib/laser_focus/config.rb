require "yaml"
require "ostruct"

module LaserFocus
  class Config
    class MissingKey < StandardError; end

    REQUIRED_PATHS = [
      %w[auth allowed_domains],
      %w[polling tick_seconds],
      %w[polling active_window_minutes],
      %w[polling idle_interval_minutes],
      %w[board epic_query],
      %w[board users],
      %w[board status_map],
      %w[board new_statuses],
      %w[board done_statuses],
      %w[board staleness somewhat_days],
      %w[board staleness really_days]
    ].freeze

    class << self
      def load_from_path(path)
        load_from_string(File.read(path))
      end

      def load_from_string(yaml)
        raw = YAML.safe_load(yaml, permitted_classes: [ Symbol ], aliases: true)
        validate!(raw)
        new(raw)
      end

      private

      def validate!(raw)
        REQUIRED_PATHS.each do |path|
          node = raw
          path.each do |key|
            unless node.is_a?(Hash) && node.key?(key)
              raise MissingKey, "Missing required config key: #{path.join('.')}"
            end
            node = node[key]
          end
        end
      end
    end

    def initialize(raw)
      @raw = raw
    end

    def jira
      @jira ||= JiraSection.new
    end

    def auth
      @auth ||= AuthSection.new(@raw["auth"])
    end

    def polling
      @polling ||= struct(@raw["polling"])
    end

    def board
      @board ||= BoardSection.new(@raw["board"])
    end

    # Optional. Absent when this deployment has no Jira Product Discovery
    # project to read, which leaves the roadmap features switched off.
    def discovery
      return @discovery if defined?(@discovery)
      @discovery = @raw["discovery"].present? ? DiscoverySection.new(@raw["discovery"]) : nil
    end

    # Optional. The GitHub repos whose open, ready-for-review PRs make up the
    # Reviews view. Absent, the view and its tab are switched off.
    def reviews
      return @reviews if defined?(@reviews)
      @reviews = @raw["reviews"].present? ? ReviewsSection.new(@raw["reviews"]) : nil
    end

    # The Issues view: open GitHub issues, by default in the same repos as the
    # Reviews view. On whenever reviews is set up; `issues: false` turns it off.
    def issues
      return @issues if defined?(@issues)
      raw = @raw["issues"]
      @issues = if raw == false || (raw.is_a?(Hash) && raw["enabled"] == false) || reviews.nil?
        nil
      else
        IssuesSection.new(raw.is_a?(Hash) ? raw : {}, reviews)
      end
    end

    private

    def struct(hash)
      OpenStruct.new(hash)
    end

    class JiraSection
      def base_url   = ENV.fetch("JIRA_BASE_URL")
      def email      = ENV.fetch("JIRA_EMAIL")
      def api_token  = ENV.fetch("JIRA_API_TOKEN")
    end

    class AuthSection
      def initialize(h) = @h = h
      def allowed_domains = @h["allowed_domains"] || []
      def allowed_emails  = @h["allowed_emails"]  || []
      def google_client_id     = ENV.fetch("GOOGLE_CLIENT_ID")
      def google_client_secret = ENV.fetch("GOOGLE_CLIENT_SECRET")
    end

    class DiscoverySection
      DEFAULT_LINK_TYPE_ID = "10016".freeze

      def initialize(h) = @h = h
      def now_query  = @h["now_query"]
      def next_query = @h["next_query"]
      def delivery_link_type_id = (@h["delivery_link_type_id"] || DEFAULT_LINK_TYPE_ID).to_s
      def horizon_field   = @h["horizon_field"]
      def incubator_field = @h["incubator_field"]
      def rank_field      = @h["rank_field"]

      # Landing quarters: every idea (any horizon, closed ones too) and the
      # fields that hold its target. See LandingCalendar for time_id_layout.
      def roadmap_query  = @h["roadmap_query"]
      def time_id_field  = @h["time_id_field"]
      def time_id_layout = @h["time_id_layout"]
      def codename_field = @h["codename_field"]

      # `landing_quarters: false` switches the feature off for teams that do
      # not use Time-IDs: no sync, no tags, no notices.
      def landing?
        @h["landing_quarters"] != false && roadmap_query.present? && time_id_field.present? && time_id_layout.present?
      end

      def queries
        { "now" => now_query, "next" => next_query }.compact_blank
      end

      def issue_fields
        ([ "summary", "issuelinks" ] +
          [ horizon_field, incubator_field, rank_field, time_id_field, codename_field ]).compact_blank.uniq
      end
    end

    class ReviewsSection
      DEFAULT_SOMEWHAT_DAYS = 3
      DEFAULT_REALLY_DAYS = 7
      DEFAULT_AUTHOR_SOMEWHAT_DAYS = 7
      DEFAULT_AUTHOR_REALLY_DAYS = 14
      DEFAULT_DECISION_DAYS = 30

      def initialize(h) = @h = h
      def repos = Array(@h["repos"]).map(&:to_s).compact_blank.uniq(&:downcase)
      # Logins whose PRs never show, e.g. dependency bots.
      def exclude_authors = Array(@h["exclude_authors"]).map { |a| a.to_s.downcase }
      # How long a PR may wait on reviewers (or on whoever merges) before it is
      # flagged stale and then critical.
      def somewhat_days = days(%w[staleness somewhat_days], DEFAULT_SOMEWHAT_DAYS)
      def really_days   = days(%w[staleness really_days], DEFAULT_REALLY_DAYS)
      # The same, for a PR that waits on its own author. Slower, so it does not
      # shout at reviewers about work that is not theirs.
      def author_somewhat_days = days(%w[author_staleness somewhat_days], DEFAULT_AUTHOR_SOMEWHAT_DAYS)
      def author_really_days   = days(%w[author_staleness really_days], DEFAULT_AUTHOR_REALLY_DAYS)
      # A PR open this long needs a decision: merge it, close it, or snooze it
      # with the reason it stays open.
      def decision_days = (@h["decision_days"] || DEFAULT_DECISION_DAYS).to_i
      def github_token = ENV["GITHUB_TOKEN"].presence

      private

      def days(path, default) = (@h.dig(*path) || default).to_i
    end

    class IssuesSection
      # [somewhat, really] days per column. Waiting on the team is urgent; an
      # issue waiting on its reporter goes stale slowly (nudge them or close
      # it), and the team's own backlog slower still.
      DEFAULTS = {
        "team" => [ 3, 7 ],
        "reporter" => [ 14, 30 ],
        "backlog" => [ 30, 90 ]
      }.freeze
      DEFAULT_DECISION_DAYS = 90

      def initialize(h, reviews)
        @h = h
        @reviews = reviews
      end

      def repos
        list = Array(@h["repos"]).map(&:to_s).compact_blank.uniq(&:downcase)
        list.any? ? list : @reviews.repos
      end

      # Logins whose issues never show, e.g. bots. Defaults to the reviews list.
      def exclude_authors
        @h.key?("exclude_authors") ? Array(@h["exclude_authors"]).map { |a| a.to_s.downcase } : @reviews.exclude_authors
      end

      # waiting: "team", "reporter" or "backlog".
      def thresholds(waiting)
        somewhat, really = DEFAULTS.fetch(waiting)
        conf = @h.dig("staleness", waiting) || {}
        [ (conf["somewhat_days"] || somewhat).to_i, (conf["really_days"] || really).to_i ]
      end

      # An issue open this long needs a decision: fix it, close it, or snooze it
      # with the reason it stays open.
      def decision_days = (@h["decision_days"] || DEFAULT_DECISION_DAYS).to_i
      def github_token = @reviews.github_token
    end

    class BoardSection
      DEFAULT_SNOOZE_DAYS = 7
      DEFAULT_LEAD_MINUTES = 60

      def initialize(h) = @h = h
      def epic_query  = @h["epic_query"]
      def closed_epics_query = @h["closed_epics_query"]
      def unplanned_query = @h["unplanned_query"]
      def new_unplanned_query = @h["new_unplanned_query"]
      def new_unplanned_days  = @h.fetch("new_unplanned_days", 10)
      def users       = (@h["users"] || []).map { |u| OpenStruct.new(u) }
      def status_map  = @h["status_map"]
      def new_statuses  = @h["new_statuses"]
      # Epics carrying this label are continuous work: they never finish, so the
      # board treats them as a lane of their own rather than as stalled focus.
      # A single label or a list, so a team can move epics from one label to
      # another without the lane flickering in between.
      def ongoing_label = @h["ongoing_label"]
      # Epics carrying this label also get the Community view. Leave it out to
      # hide that tab.
      def community_label = @h["community_label"]
      def done_statuses = @h["done_statuses"]
      def staleness  = OpenStruct.new(@h["staleness"])
      # How long a snoozed stale ticket stays out of the highlight.
      def snooze_days = (@h.dig("staleness", "snooze_days") || DEFAULT_SNOOZE_DAYS).to_i
      # The day thresholds (stale, critical, snooze end) all fire this much
      # early, so a ticket touched during a daily meeting is flagged again
      # before the same meeting days later, not halfway through it.
      def staleness_lead = (@h.dig("staleness", "lead_minutes") || DEFAULT_LEAD_MINUTES).to_i.minutes
      def ignore_staleness_for_new_issues
        @h.fetch("ignore_staleness_for_new_issues", true)
      end
    end
  end
end
