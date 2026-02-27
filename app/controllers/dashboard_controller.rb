# frozen_string_literal: true

class DashboardController < ApplicationController
  def show
    # Determinar año seleccionado (desde parámetro o sesión, default a año actual)
    selected_year = params[:year]&.to_i || session[:selected_year]&.to_i || Date.current.year
    session[:selected_year] = selected_year

    # Filtrar tickets y trips por año seleccionado
    @selected_year = selected_year

    # Filtrar tickets por año creado
    year_start = Date.new(selected_year, 1, 1)
    year_end = Date.new(selected_year, 12, 31)

    @tickets = current_user.tickets
                            .where(created_at: year_start.beginning_of_day..year_end.end_of_day)
                            .order(created_at: :desc)

    # Filtrar trips por año de salida
    @trips = current_user.trips
                         .where(departure_date: year_start..year_end)
                         .order(departure_date: :asc)

    @pending_parse_count = @tickets.count(&:pending_parse?)
  end
end
