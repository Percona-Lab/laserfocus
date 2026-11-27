class StaleSnoozesController < ApplicationController
  def update
    key, state = snooze_target(params[:key].to_s)
    return head :not_found unless key

    snooze = StaleSnooze.find_or_initialize_by(jira_key: key)
    snooze.update!(
      jira_status: state,
      snoozed_until: (LASER_FOCUS_CONFIG.board.snooze_days.days - LASER_FOCUS_CONFIG.board.staleness_lead).from_now,
      snoozed_by: session[:user_name].presence || current_user_email,
      reason: params[:reason].to_s.strip.first(StaleSnooze::REASON_LIMIT).presence
    )
    broadcast(key)
    head :no_content
  end

  def destroy
    key = params[:key].to_s
    deleted = StaleSnooze.where(jira_key: key).delete_all
    broadcast(key) if deleted.positive?
    head :no_content
  end

  private

  # The board shows the Reviews and Issues tabs' red counts, so a PR or issue
  # snooze refreshes the board too.
  def broadcast(key)
    if GithubKeyed.key?(key)
      GithubIssue.find_by_key(key) ? BoardBroadcasts.issues : BoardBroadcasts.reviews
    end
    BoardBroadcasts.board
  end

  # A Jira ticket on the board, an open PR or issue on the Reviews or Issues
  # view, or a roadmap idea with landing warnings. Returns the key to store and
  # the state the snooze holds for.
  def snooze_target(raw)
    if GithubKeyed.key?(raw)
      item = GithubKeyed.find(raw)
      item && [ item.key, item.snooze_state ]
    elsif (issue = Issue.active.find_by(jira_key: raw))
      [ issue.jira_key, issue.jira_status ]
    elsif (board = LandingBoard.build) && (assessment = board.find(raw))
      state = board.warning_state(assessment)
      state && [ raw, state ]
    end
  end
end
