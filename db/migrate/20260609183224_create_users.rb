class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.datetime :last_seen_at, null: false

      t.timestamps
    end
  end
end
