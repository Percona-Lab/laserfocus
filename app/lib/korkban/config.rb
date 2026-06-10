require "yaml"
require "ostruct"

module Korkban
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

    class BoardSection
      def initialize(h) = @h = h
      def epic_query  = @h["epic_query"]
      def unplanned_query = @h["unplanned_query"]
      def users       = (@h["users"] || []).map { |u| OpenStruct.new(u) }
      def status_map  = @h["status_map"]
      def new_statuses  = @h["new_statuses"]
      def done_statuses = @h["done_statuses"]
      def staleness  = OpenStruct.new(@h["staleness"])
      def ignore_staleness_for_new_issues
        @h.fetch("ignore_staleness_for_new_issues", true)
      end
    end
  end
end
