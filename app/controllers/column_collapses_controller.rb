class ColumnCollapsesController < ApplicationController
  def update
    key = params[:key].to_s
    allowed = Epic.active.pluck(:jira_key).to_set << BoardPresenter::UNPLANNED_EPIC.jira_key
    if allowed.include?(key)
      order = BoardOrder.instance
      keys = order.collapsed_columns.select { |k| allowed.include?(k) } - [ key ]
      keys << key if ActiveModel::Type::Boolean.new.cast(params[:collapsed])
      order.update!(collapsed_columns: keys)
      BoardBroadcasts.board if order.saved_changes?
    end
    head :no_content
  end
end
