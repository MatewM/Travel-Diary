# frozen_string_literal: true

class ConfidenceCalculatorService
  # flight_date reemplaza departure_datetime/arrival_datetime
  # tras el cambio del prompt de Gemini
  CRITICAL_FIELDS = %i[departure_airport arrival_airport flight_date].freeze
  REQUIRED_CONFIDENCE_FIELDS = %i[flight_number airline departure_airport
                                  arrival_airport flight_date passenger_name].freeze

  def self.call(parsed_data)
    new(parsed_data).call
  end

  def initialize(parsed_data)
    @data = parsed_data.with_indifferent_access
  end

  def call
    issues = []

    # Signal 1 — campos críticos ausentes (nil o vacíos)
    CRITICAL_FIELDS.each do |field|
      issues << field if @data[field].blank?
    end

    # Signal 2 — formato IATA inválido en aeropuertos
    %i[departure_airport arrival_airport].each do |field|
      val = @data[field].to_s
      issues << field if val.present? && val !~ /\A[A-Z]{3}\z/
    end

    # Signal 3 — aeropuerto no encontrado en la DB
    %i[departure_airport arrival_airport].each do |field|
      val = @data[field].to_s
      issues << field if val.present? && !Airport.exists?(iata_code: val)
    end

    # Signal 4 — confianza baja declarada por el propio Gemini
    # Horas son opcionales — no penalizar si faltan
    %i[departure_time arrival_time].each do |opt_field|
      next unless @data[:confidence][opt_field]
      issues << opt_field.to_sym if @data[:confidence][opt_field] == "low"
    end

    # Campos obligatorios sí penalizan
    REQUIRED_CONFIDENCE_FIELDS.each do |field|
      issues << field.to_sym if @data[:confidence][field] == "low"
    end

    issues.uniq!

    # PRIORIDAD FISCAL: Para residencia fiscal solo importa PAÍS + DÍA
    # Airline, flightnumber, hora exacta son detalles secundarios
    airports_ok = (issues & [:departure_airport, :arrival_airport]).empty?

    # Signal 5 - validar flight_date
    if @data["flight_date"].present?
      begin
        Date.parse(@data["flight_date"])
        has_valid_date = true
      rescue ArgumentError
        issues << :flight_date
      end
    else
      issues << :flight_date # Penalizar si no hay fecha
    end

    if airports_ok && has_valid_date
      { level: "high", status: "auto_verified", issues: [] }
    elsif issues.count <= 2
      { level: "medium", status: "needs_review", issues: issues }
    else
      { level: "low", status: "manual_required", issues: issues }
    end
  end
end