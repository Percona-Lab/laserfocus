module ApplicationHelper
  def jira_url(key)
    "#{LASER_FOCUS_CONFIG.jira.base_url}/browse/#{key}"
  end
end
