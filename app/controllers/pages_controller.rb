# frozen_string_literal: true

class PagesController < ApplicationController
  def home
    redirect_to dashboard_path if user_signed_in?
  end
end
