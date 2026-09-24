class NextController < ApplicationController
  def show
    @presenter = NextPresenter.build
    @configured = LASER_FOCUS_CONFIG.discovery.present?
    @last_sync = SyncRun.ok.most_recent.first
    # Same count as on the board, see BoardController.
    @warnings = BoardPresenter.build.warnings
  end
end
