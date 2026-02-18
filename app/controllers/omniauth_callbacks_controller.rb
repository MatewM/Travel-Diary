# frozen_string_literal: true

class OmniauthCallbacksController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :verify_authenticity_token, only: :create

  def create
    auth = request.env["omniauth.auth"]

    unless auth&.info&.email.present?
      Rails.logger.warn "[OAuth] Intento sin datos válidos"
      return redirect_to root_path, alert: "No se recibieron datos válidos del proveedor."
    end

    user = User.from_omniauth(auth)
    start_new_session_for(user)
    redirect_to dashboard_path
  rescue StandardError => e
    Rails.logger.error "[OAuth] Error: #{e.class} - #{e.message}"
    redirect_to root_path, alert: "Error al crear la cuenta. Por favor, inténtalo de nuevo."
  end

  def failure
    Rails.logger.warn "[OAuth] Fallo: #{params[:message]}"
    redirect_to root_path, alert: "No se pudo iniciar sesión. Por favor, inténtalo de nuevo."
  end
end
