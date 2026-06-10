class User < ApplicationRecord
  def self.singleton
    first || create!(last_seen_at: Time.at(0))
  end

  def self.touch_now!
    singleton.update!(last_seen_at: Time.current)
  end
end
