# frozen_string_literal: true

class SessionsController < ApplicationController
  allow_unauthenticated_access only: [:new, :create]

  rate_limit to: 10, within: 3.minutes, only: :create, with: -> {
    redirect_to new_session_url, alert: "Demasiados intentos. Intenta de nuevo más tarde."
  }

  def new
  end

  def create
    if (user = User.authenticate_by(email: params[:email], password: params[:password]))
      start_new_session_for(user)
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Email o contraseña incorrectos."
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, notice: "Sesión cerrada correctamente."
  end
end
