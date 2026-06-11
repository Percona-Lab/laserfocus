Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           LASER_FOCUS_CONFIG.auth.google_client_id,
           LASER_FOCUS_CONFIG.auth.google_client_secret,
           name: "google_oauth2"
end

OmniAuth.config.allowed_request_methods = [ :post, :get ]
OmniAuth.config.silence_get_warning     = true
