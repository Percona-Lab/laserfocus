class SyncRun < ApplicationRecord
  scope :ok,         -> { where(ok: true) }
  scope :most_recent, -> { order(started_at: :desc) }
end
