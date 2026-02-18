# frozen_string_literal: true

class PagesController < ApplicationController
  allow_unauthenticated_access

  def home
    redirect_to dashboard_path if authenticated?
  end
end
