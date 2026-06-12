class CreateBoardOrders < ActiveRecord::Migration[8.1]
  def up
    create_table :board_orders do |t|
      t.json :column_order, null: false, default: []
      t.timestamps
    end

    seed = [ "UNPLANNED" ] + select_values(
      "SELECT jira_key FROM epics WHERE removed_at IS NULL ORDER BY priority ASC, name ASC"
    )
    execute(<<~SQL)
      INSERT INTO board_orders (column_order, created_at, updated_at)
      VALUES ('#{seed.to_json}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
  end

  def down
    drop_table :board_orders
  end
end
