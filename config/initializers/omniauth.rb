# frozen_string_literal: true

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           ENV.fetch("GOOGLE_CLIENT_ID", ""),
           ENV.fetch("GOOGLE_CLIENT_SECRET", ""),
           scope: "email,profile",
           prompt: "select_account"

  provider :apple,
           ENV.fetch("APPLE_CLIENT_ID", ""),
           ENV.fetch("APPLE_TEAM_ID", ""),
           key_id: ENV.fetch("APPLE_KEY_ID", ""),
           pem: ENV.fetch("APPLE_PRIVATE_KEY", "").gsub("\\n", "\n"),
           scope: "email name"
end

# Misma ruta que usaba Devise para no cambiar la config de Google Console
OmniAuth.config.path_prefix = "/users/auth"
OmniAuth.config.allowed_request_methods = %i[post]
OmniAuth.config.silence_get_warning = true
