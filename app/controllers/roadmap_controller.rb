# /roadmap: internal landing quarters over a year. Not linked from the view
# tabs; the roadmap line on the board links here.
class RoadmapController < ApplicationController
  def show
    @presenter = RoadmapPresenter.build(params.permit(:range, :quarter, :idea, :changes))
  end
end
