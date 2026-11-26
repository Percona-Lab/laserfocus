class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  before_action :require_login
  before_action :touch_user

  helper_method :current_user_email, :excluded_repos

  private

  def require_login
    redirect_to "/login" unless session[:user_email]
  end

  def touch_user
    User.touch_now!
  end

  def current_user_email
    session[:user_email]
  end

  # Repos the viewer took out of their Reviews and Issues views, lowercased.
  # The tab counts on every view leave them out too.
  def excluded_repos
    @excluded_repos ||= RepoExclusion.repos_for(current_user_email)
  end
end
