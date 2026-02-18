# frozen_string_literal: true

class DashboardController < ApplicationController
  def show
    @tickets = current_user.tickets.order(created_at: :desc)
  end
end
