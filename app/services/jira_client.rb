require "jira-ruby"

class JiraClient
  PAGE_SIZE = 50

  def initialize(cfg: KORKBAN_CONFIG.jira)
    @client = JIRA::Client.new(
      username:     cfg.email,
      password:     cfg.api_token,
      site:         cfg.base_url,
      context_path: "",
      auth_type:    :basic
    )
  end

  def search_all(jql, fields: nil, expand: nil)
    @client.Issue.jql(jql, max_results: PAGE_SIZE, fields: fields, expand: expand)
  end
end
