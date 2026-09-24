class NextController < ApplicationController
  def show
    @presenter = NextPresenter.build
    @configured = LASER_FOCUS_CONFIG.discovery.present?
    @last_sync = SyncRun.ok.most_recent.first
  end
end
