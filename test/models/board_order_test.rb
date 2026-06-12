require "test_helper"

class BoardOrderTest < ActiveSupport::TestCase
  test "instance returns a singleton row" do
    BoardOrder.delete_all
    first = BoardOrder.instance
    assert_equal [], first.column_order
    assert_equal first.id, BoardOrder.instance.id
    assert_equal 1, BoardOrder.count
  end

  test "instance reuses an existing row" do
    BoardOrder.delete_all
    existing = BoardOrder.create!(column_order: [ "PG-2", "PG-1" ])
    assert_equal existing.id, BoardOrder.instance.id
    assert_equal [ "PG-2", "PG-1" ], BoardOrder.instance.column_order
  end
end
