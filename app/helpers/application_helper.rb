module ApplicationHelper
  def jira_url(key)
    "#{KORKBAN_CONFIG.jira.base_url}/browse/#{key}"
  end
end
