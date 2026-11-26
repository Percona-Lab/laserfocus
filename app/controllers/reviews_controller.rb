class ReviewsController < ApplicationController
  include GithubViewer

  def show
    @configured = LASER_FOCUS_CONFIG.reviews.present?
    @presenter = ReviewsPresenter.build(viewer: viewer, excluded: excluded_repos) if @configured
    @review_sync = ReviewSyncRun.pulls.most_recent.first
    @last_sync = SyncRun.ok.most_recent.first
    # Same count as on the board, see BoardController.
    @warnings = BoardPresenter.build.warnings
  end
end
