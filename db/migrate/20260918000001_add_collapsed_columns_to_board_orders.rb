class AddCollapsedColumnsToBoardOrders < ActiveRecord::Migration[8.1]
  def change
    add_column :board_orders, :collapsed_columns, :json, null: false, default: []
  end
end
