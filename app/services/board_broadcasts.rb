module BoardBroadcasts
  def self.board
    Turbo::StreamsChannel.broadcast_refresh_to("board")
  end
end
