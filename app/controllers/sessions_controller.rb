class SessionsController < ApplicationController
  skip_before_action :require_login,   only: %i[new create failure]
  skip_before_action :touch_user,      only: %i[new create failure]

  def new
  end

  def create
    info  = request.env["omniauth.auth"].info
    email = info.email.to_s.downcase
    if allowed?(email)
      session[:user_email] = email
      session[:user_name]  = info.name
      redirect_to root_path
    else
      redirect_to "/login", alert: "Not authorized for #{email}"
    end
  end

  def failure
    redirect_to "/login", alert: "Sign-in failed"
  end

  def destroy
    reset_session
    redirect_to "/login"
  end

  private

  def allowed?(email)
    return false if email.blank?
    domain = email.split("@", 2).last
    LASER_FOCUS_CONFIG.auth.allowed_emails.include?(email) ||
      LASER_FOCUS_CONFIG.auth.allowed_domains.include?(domain)
  end
end
