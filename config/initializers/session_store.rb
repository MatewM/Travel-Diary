# frozen_string_literal: true

# Cookies de sesión seguras (httponly, secure en producción)
Rails.application.config.session_store :cookie_store,
  key: "_travel_diary_session",
  httponly: true,
  secure: Rails.env.production?,
  same_site: :lax
