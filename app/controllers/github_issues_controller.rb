# The Issues view: open GitHub issues in the watched repos. Named apart from
# the Jira issues the board is made of.
class GithubIssuesController < ApplicationController
  include GithubViewer

  def show
    @configured = LASER_FOCUS_CONFIG.issues.present?
    @presenter = IssuesPresenter.build(viewer: viewer, excluded: excluded_repos) if @configured
    @issue_sync = ReviewSyncRun.issues.most_recent.first
    @last_sync = SyncRun.ok.most_recent.first
    # Same count as on the board, see BoardController.
    @warnings = BoardPresenter.build.warnings
  end
end
