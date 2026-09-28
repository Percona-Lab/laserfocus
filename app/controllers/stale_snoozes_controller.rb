class StaleSnoozesController < ApplicationController
  def update
    issue = Issue.active.find_by(jira_key: params[:key].to_s)
    return head :not_found unless issue

    snooze = StaleSnooze.find_or_initialize_by(jira_key: issue.jira_key)
    snooze.update!(
      jira_status: issue.jira_status,
      snoozed_until: LASER_FOCUS_CONFIG.board.snooze_days.days.from_now,
      snoozed_by: session[:user_name].presence || current_user_email,
      reason: params[:reason].to_s.strip.first(StaleSnooze::REASON_LIMIT).presence
    )
    BoardBroadcasts.board
    head :no_content
  end

  def destroy
    deleted = StaleSnooze.where(jira_key: params[:key].to_s).delete_all
    BoardBroadcasts.board if deleted.positive?
    head :no_content
  end
end
