class SyncsController < ApplicationController
  def create
    JiraSyncJob.perform_later
    head :no_content
  end
end
