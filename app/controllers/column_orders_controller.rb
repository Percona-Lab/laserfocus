class ColumnOrdersController < ApplicationController
  def update
    keys = Array(params[:order]).map(&:to_s)
    allowed = Epic.active.pluck(:jira_key).to_set << BoardPresenter::UNPLANNED_EPIC.jira_key
    BoardOrder.instance.update!(column_order: keys.select { |k| allowed.include?(k) })
    BoardBroadcasts.board
    head :no_content
  end
end
