class GapDetectorService
  def self.call(user, year)
    new(user, year).call
  end

  def initialize(user, year)
    @user = user
    @year = year
    @year_start = Date.new(year, 1, 1)
    @year_end = Date.new(year, 12, 31)
  end

  def call
    trips = load_trips_for_year
    inherited_trip = load_inherited_trip

    rows = []

    # Insertar inherited_trip como primera fila si existe
    if inherited_trip
      rows << build_inherited_trip_row(inherited_trip)
    end

    # Procesar cada trip del año
    trips.each_with_index do |trip, index|
      # Añadir fila del trip
      rows << build_trip_row(trip)

      # Si no es el último trip, verificar gap con el siguiente
      next_trip = trips[index + 1]
      if next_trip
        gap_row = detect_gap_between_trips(trip, next_trip)
        rows << gap_row if gap_row
      end
    end

    rows
  end

  private

  def load_trips_for_year
    @user.trips
      .includes(:origin_country, :destination_country)
      .where("departure_date >= ? AND arrival_date <= ?", @year_start, @year_end)
      .order(:departure_date)
  end

  def load_inherited_trip
    @user.trips
      .includes(:destination_country)
      .where("arrival_date >= ? AND departure_date < ?", @year_start, @year_start)
      .order(arrival_date: :desc)
      .first
  end

  def build_inherited_trip_row(inherited_trip)
    end_date = trips_for_year.first&.departure_date&.-(1.day) || @year_end

    {
      type: :inherited_trip,
      country: inherited_trip.destination_country,
      start_date: @year_start,
      end_date: [end_date, @year_end].min,
      days: calculate_days(@year_start, [end_date, @year_end].min),
      trip_id: inherited_trip.id,
      has_boarding_pass: inherited_trip.has_boarding_pass,
      manually_entered: inherited_trip.manually_entered,
      gap_type: nil,
      gap_message: nil,
      origin_country: nil
    }
  end

  def build_trip_row(trip)
    # Encontrar el siguiente trip del usuario (no solo del año)
    next_trip = find_next_trip_after(trip)
    end_date = next_trip ? next_trip.departure_date - 1.day : nil

    {
      type: :trip,
      country: trip.destination_country,
      start_date: trip.arrival_date,
      end_date: end_date,
      days: calculate_days(trip.arrival_date, end_date || Date.today),
      trip_id: trip.id,
      has_boarding_pass: trip.has_boarding_pass,
      manually_entered: trip.manually_entered,
      gap_type: nil,
      gap_message: nil,
      origin_country: trip.origin_country
    }
  end

  def detect_gap_between_trips(trip_a, trip_b)
    # Calcular fecha de salida efectiva del trip anterior
    end_date_of_stay = trip_b.departure_date - 1.day
    days_in_country = calculate_days(trip_a.arrival_date, end_date_of_stay)

    # Prioridad 1: Gap geográfico
    if trip_a.destination_country_id != trip_b.origin_country_id
      return {
        type: :gap,
        country: nil,
        start_date: end_date_of_stay + 1.day,
        end_date: trip_b.arrival_date - 1.day,
        days: calculate_days(end_date_of_stay + 1.day, trip_b.arrival_date - 1.day),
        trip_id: nil,
        has_boarding_pass: false,
        manually_entered: false,
        gap_type: :geographic,
        gap_message: "Saliste de #{trip_a.destination_country&.name} pero no hay registro de cómo llegaste allí.",
        origin_country: trip_b.origin_country
      }
    end

    # Prioridad 2: Gap temporal (solo si no hay geográfico)
    if trip_b.departure_date > trip_a.arrival_date + 1.day
      gap_days = (trip_b.departure_date - trip_a.arrival_date).to_i - 1
      return {
        type: :gap,
        country: nil,
        start_date: end_date_of_stay + 1.day,
        end_date: trip_b.arrival_date - 1.day,
        days: gap_days,
        trip_id: nil,
        has_boarding_pass: false,
        manually_entered: false,
        gap_type: :temporal,
        gap_message: "Hay #{gap_days} días entre tu salida de #{trip_a.destination_country&.name} y tu siguiente registro.",
        origin_country: nil
      }
    end

    nil # No hay gap
  end

  def find_next_trip_after(trip)
    @user.trips
      .where("departure_date > ?", trip.departure_date)
      .order(:departure_date)
      .first
  end

  def trips_for_year
    @trips_for_year ||= load_trips_for_year
  end

  def calculate_days(start_date, end_date)
    return 0 if end_date < start_date
    (end_date - start_date).to_i + 1
  end
end
