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

      def queries
        { "now" => now_query, "next" => next_query }.compact_blank
      end

      def issue_fields
        ([ "summary", "issuelinks" ] + [ horizon_field, incubator_field, rank_field ]).compact_blank.uniq
      end
    end

    class BoardSection
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
      def ongoing_label = @h["ongoing_label"]
      def done_statuses = @h["done_statuses"]
      def staleness  = OpenStruct.new(@h["staleness"])
      def ignore_staleness_for_new_issues
        @h.fetch("ignore_staleness_for_new_issues", true)
      end
    end
  end
end
