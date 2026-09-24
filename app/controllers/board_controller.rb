class BoardController < ApplicationController
  ACTIVITY_HIGHLIGHT_DAYS = [ 1, 3, 7, 30 ].freeze

  def show
    @group_mode = group_mode_from_cookie
    @expand_all = expand_all_param?
    @view = params[:view] == "community" ? :community : :board
    @presenter = BoardPresenter.build(group_mode: @group_mode, expand_all: @expand_all, view: @view)
    @last_sync = SyncRun.ok.most_recent.first
    @activity_days = ACTIVITY_HIGHLIGHT_DAYS
  end

  private

  def group_mode_from_cookie
    raw = cookies[:board_group_mode].to_s
    BoardPresenter::GROUP_MODES.include?(raw) ? raw : BoardPresenter::DEFAULT_GROUP_MODE
  end

  def expand_all_param?
    ActiveModel::Type::Boolean.new.cast(params[:expand_all]) || false
  end
end
