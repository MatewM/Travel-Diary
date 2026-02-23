# frozen_string_literal: true

class ConfidenceCalculatorService
  # flight_date reemplaza departure_datetime/arrival_datetime
  # tras el cambio del prompt de Gemini
  CRITICAL_FIELDS = %i[departure_airport arrival_airport flight_date].freeze
  CORE_CONFIDENCE_FIELDS = %i[departure_airport arrival_airport flight_date].freeze

  def self.call(parsed_data)
    new(parsed_data).call
  end

  def initialize(parsed_data)
    @data = (parsed_data || {}).with_indifferent_access
  end

  def call
    issues = []
    has_valid_date = false # Inicialización para evitar el error de variable no definida

    # Signal 1 — campos críticos ausentes (nil o vacíos)
    CRITICAL_FIELDS.each do |field|
      issues << field if @data[field].blank?
    end

    # Signal 2 — formato IATA inválido en aeropuertos
    %i[departure_airport arrival_airport].each do |field|
      val = @data[field].to_s
      issues << field if val.present? && val !~ /\A[A-Z]{3}\z/
    end

    # TODO: Revisar y reactivar en el futuro cuando la base de datos de Airports
    # esté enriquecida con todos los aeropuertos mundiales.
    # Signal 3 — aeropuerto no encontrado en la DB
    # %i[departure_airport arrival_airport].each do |field|
    #   val = @data[field].to_s
    #   issues << field if val.present? && !Airport.exists?(iata_code: val)
    # end

    # Signal 4 — ELIMINADO: Las horas son opcionales y no afectan el estado del ticket
    # No penalizar campos opcionales (departure_time, arrival_time) por baja confianza
    # %i[departure_time arrival_time].each do |opt_field|
    #   next unless @data.dig(:confidence, opt_field.to_s)
    #   issues << opt_field.to_sym if @data.dig(:confidence, opt_field.to_s) == "low" && !has_valid_date
    # end

    # Campos obligatorios sí penalizan
    CORE_CONFIDENCE_FIELDS.each do |field|
      issues << field.to_sym if @data.dig(:confidence, field.to_s) != "high"
    end

    # Signal X: year_requires_verification — Gemini no pudo confirmar el año con certeza
    if @data["year_requires_verification"] == true
      issues << :year_requires_verification
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
        has_valid_date = false
      end
    else
      issues << :flight_date # Penalizar si no hay fecha
      has_valid_date = false # Explicitly set to false if date is missing or invalid
    end

    # Determinar si el modal de revisión debe abrirse automáticamente.
    # NO lanzar modal si: aeropuertos ambos high Y flight_date high o medium (solo año incierto).
    # SÍ lanzar modal si: cualquier aeropuerto no es high, o flight_date es low/nil.
    airports_confidence_high = @data.dig("confidence", "departure_airport") == "high" &&
                               @data.dig("confidence", "arrival_airport") == "high"
    flight_date_conf = @data.dig("confidence", "flight_date")
    launch_modal = !airports_confidence_high || !%w[high medium].include?(flight_date_conf.to_s)

    # La lógica para decidir si es auto_verified debe ser más estricta
    # Consideramos un ticket auto_verified si:
    # 1. Los aeropuertos son válidos y encontrados en la DB
    # 2. La fecha de vuelo es válida
    # 3. No hay otros 'issues' que comprometan la verificación automática
    if issues.empty? && airports_ok && has_valid_date
      { level: "high", status: "auto_verified", issues: [], launch_modal: false }
    elsif issues.count <= 2
      { level: "medium", status: "needs_review", issues: issues, launch_modal: launch_modal }
    else
      { level: "low", status: "manual_required", issues: issues, launch_modal: true }
    end
  end
end