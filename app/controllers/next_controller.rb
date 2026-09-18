class NextController < ApplicationController
  def show
    @presenter = NextPresenter.build
    @configured = LASER_FOCUS_CONFIG.discovery.present?
  end
end
