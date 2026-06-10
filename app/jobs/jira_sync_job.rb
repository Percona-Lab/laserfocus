class JiraSyncJob < ApplicationJob
  queue_as :default

  limits_concurrency key: "jira_sync", to: 1, duration: 15.minutes, on_conflict: :discard

  def perform
    user = User.singleton
    active_window = KORKBAN_CONFIG.polling.active_window_minutes.minutes
    idle_interval = KORKBAN_CONFIG.polling.idle_interval_minutes.minutes

    active = user.last_seen_at && user.last_seen_at >= Time.current - active_window

    unless active
      last_ok = SyncRun.ok.most_recent.first
      if last_ok && last_ok.started_at && last_ok.started_at >= Time.current - idle_interval
        Rails.logger.info("[JiraSyncJob] idle and recent sync exists, skipping")
        return
      end
    end

    JiraSync.new.run!
  end
end
