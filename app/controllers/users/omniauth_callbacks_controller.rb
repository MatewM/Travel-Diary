# frozen_string_literal: true

module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_before_action :verify_authenticity_token, only: [:apple]

    def google_oauth2
      handle_oauth("Google")
    end

    def apple
      handle_oauth("Apple")
    end

    def failure
      Rails.logger.warn "[OAuth] Fallo de autenticación: #{failure_message}"
      redirect_to root_path, alert: "No se pudo iniciar sesión. Por favor, inténtalo de nuevo."
    end

    private

    def handle_oauth(provider_name)
      auth = request.env["omniauth.auth"]

      unless auth&.info&.email.present?
        Rails.logger.warn "[OAuth] Intento de #{provider_name} sin datos válidos"
        return redirect_to root_path, alert: "No se recibieron datos válidos del proveedor."
      end

      unless valid_oauth_origin?(auth)
        Rails.logger.warn "[OAuth] Proveedor no reconocido: #{auth.provider}"
        return redirect_to root_path, alert: "Proveedor de autenticación no reconocido."
      end

      user = User.from_omniauth(auth)
      sign_in_and_redirect user, event: :authentication
      set_flash_message(:notice, :success, kind: provider_name) if is_navigational_format?
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[OAuth] Error de registro: #{e.message}"
      redirect_to root_path, alert: "Error al crear la cuenta. Por favor, inténtalo de nuevo."
    rescue StandardError => e
      Rails.logger.error "[OAuth] Error inesperado: #{e.class} - #{e.message}"
      redirect_to root_path, alert: "Error inesperado. Por favor, inténtalo de nuevo."
    end

    def valid_oauth_origin?(auth)
      %w[google_oauth2 apple].include?(auth.provider)
    end
  end
end
