class CreateBoardSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :board_snapshots do |t|
      t.integer :version, null: false, default: 0

      t.timestamps
    end
  end
end
