# Takes a repo out of, or back into, the signed-in viewer's Reviews and Issues
# views. Nobody else's page changes, so nothing is broadcast: the viewer's page
# refreshes itself after the request.
class RepoExclusionsController < ApplicationController
  def update
    repo = params[:repo].to_s.downcase
    return head :not_found unless RepoExclusion.watchable.include?(repo)

    scope = RepoExclusion.where(user_email: current_user_email.to_s.downcase, repo: repo)
    if ActiveModel::Type::Boolean.new.cast(params[:excluded])
      scope.first_or_create!
    else
      scope.delete_all
    end
    head :no_content
  end
end
