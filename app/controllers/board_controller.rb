class BoardController < ApplicationController
  ACTIVITY_HIGHLIGHT_DAYS = [ 1, 3, 7, 30 ].freeze

  def show
    @presenter = BoardPresenter.new(
      epics: Epic.active.ordered.includes(:issues),
      orphan_issues: Issue.active.orphan,
      status_map: LASER_FOCUS_CONFIG.board.status_map,
      new_statuses: LASER_FOCUS_CONFIG.board.new_statuses,
      done_statuses: LASER_FOCUS_CONFIG.board.done_statuses,
      staleness: StalenessCalculator.new(
        now: Time.current,
        somewhat_days: LASER_FOCUS_CONFIG.board.staleness.somewhat_days,
        really_days: LASER_FOCUS_CONFIG.board.staleness.really_days,
        ignore_for_new: LASER_FOCUS_CONFIG.board.ignore_staleness_for_new_issues,
        new_display_statuses: LASER_FOCUS_CONFIG.board.new_statuses,
        done_display_statuses: LASER_FOCUS_CONFIG.board.done_statuses
      )
    )
    @last_sync = SyncRun.ok.most_recent.first
    @activity_days = ACTIVITY_HIGHLIGHT_DAYS
  end
end
