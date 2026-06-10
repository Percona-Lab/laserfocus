require "jira-ruby"

class JiraClient
  PAGE_SIZE = 100
  MAX_RETRIES = 5
  MAX_RETRY_WAIT = 60
  DEFAULT_BACKOFF = 2

  def initialize(cfg: KORKBAN_CONFIG.jira)
    @client = JIRA::Client.new(
      username:     cfg.email,
      password:     cfg.api_token,
      site:         cfg.base_url,
      context_path: "",
      auth_type:    :basic
    )
    install_rate_limit_retry(@client.request_client)
  end

  def search_all(jql, fields: nil, expand: nil)
    @client.Issue.jql(jql, max_results: PAGE_SIZE, fields: fields, expand: expand)
  end

  private

  def install_rate_limit_retry(request_client)
    request_client.singleton_class.prepend(RateLimitRetry)
  end

  module RateLimitRetry
    def request(*args)
      attempt = 0
      begin
        super
      rescue JIRA::HTTPError => e
        raise unless e.response&.code.to_s == "429"
        attempt += 1
        raise if attempt > JiraClient::MAX_RETRIES
        wait = JiraClient.retry_after_seconds(e.response, attempt)
        Rails.logger.warn("[JiraClient] 429 rate limited; retry #{attempt}/#{JiraClient::MAX_RETRIES} in #{wait}s")
        JiraClient.pause(wait)
        retry
      end
    end
  end

  def self.pause(seconds)
    sleep(seconds)
  end

  def self.retry_after_seconds(response, attempt)
    header = response["Retry-After"] || response["retry-after"]
    seconds =
      if header.nil? || header.empty?
        DEFAULT_BACKOFF * (2 ** (attempt - 1))
      elsif header =~ /\A\d+\z/
        header.to_i
      else
        ((Time.httpdate(header) - Time.now).ceil rescue DEFAULT_BACKOFF * (2 ** (attempt - 1)))
      end
    seconds.clamp(1, MAX_RETRY_WAIT)
  end
end
