# frozen_string_literal: true

class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    @trips = current_user.trips.order(start_date: :desc)
    @trip = Trip.new
  end
end
