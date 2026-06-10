Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           KORKBAN_CONFIG.auth.google_client_id,
           KORKBAN_CONFIG.auth.google_client_secret,
           name: "google_oauth2"
end

OmniAuth.config.allowed_request_methods = [ :post, :get ]
OmniAuth.config.silence_get_warning     = true
