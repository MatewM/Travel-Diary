class TripsController < ApplicationController
  before_action :authenticate_user!

  def create
    @trip = current_user.trips.build(trip_params)

    if @trip.save
      redirect_to dashboard_path, notice: 'Viaje creado correctamente.'
    else
      redirect_to dashboard_path, alert: 'Error al crear el viaje.'
    end
  end

  private

  def trip_params
    params.require(:trip).permit(:destination, :start_date, :end_date, :country, tickets: [])
  end
end
