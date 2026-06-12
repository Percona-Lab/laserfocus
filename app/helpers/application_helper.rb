module ApplicationHelper
  def jira_url(key)
    "#{LASER_FOCUS_CONFIG.jira.base_url.chomp("/")}/browse/#{key}"
  end
end
