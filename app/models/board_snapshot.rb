class BoardSnapshot < ApplicationRecord
  def self.singleton
    first || create!(version: 0)
  end

  def self.bump!
    singleton.tap { |s| s.update!(version: s.version + 1) }
  end
end
