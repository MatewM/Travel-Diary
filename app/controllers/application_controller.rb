# frozen_string_literal: true

class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  def after_sign_in_path_for(_resource)
    dashboard_path
  end
end
