class BoardOrder < ApplicationRecord
  def self.instance
    first || create!(column_order: [])
  end
end
