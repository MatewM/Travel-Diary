# frozen_string_literal: true

class ParseTicketService
  # Interfaz pública: ya NO acepta capture_date desde fuera.
  # El servicio lo calcula internamente.
  def self.call(ticket_id)
    new(ticket_id).call
  end

  def initialize(ticket_id)
    @ticket_id = ticket_id
  end

  def call
    ticket = Ticket.find(@ticket_id)

    attachment = ticket.original_files.first
    unless attachment
      ticket.update_columns(status: "error", parsed_data: { error: "No file attached" }, updated_at: Time.current)
      return { success: false, error: "No file attached" }
    end

    filepath = ActiveStorage::Blob.service.path_for(attachment.blob.key)
    mimetype = attachment.content_type

    # Extraer fecha usando ticket.created_at como base robusta
    extraction_result = ExifYearExtractorService.call(ticket)

    full_date = extraction_result[:full_date]
    target_year = extraction_result[:year]
    Rails.logger.info "[ParseTicketService] Using ticket creation date=#{full_date}, target_year=#{target_year} for ticket #{@ticket_id}"

    # B. INTENTO 1 - Vía Barcode/QR
    bcbp_result = BarcodeExtractorService.call(filepath, capture_date: full_date.strftime('%Y-%m-%d'))

    if bcbp_result.present? && bcbp_result.with_indifferent_access[:source].to_s == "bcbp"
      parsed_data = bcbp_result.with_indifferent_access

      # Buscar países por IATA usando los aeropuertos
      dep_country = Airport.find_by(iata_code: parsed_data[:departure_airport])&.country
      arr_country = Airport.find_by(iata_code: parsed_data[:arrival_airport])&.country

      # Determinar status basado en si la fecha viene del BCBP o de metadata
      ticket_status = parsed_data[:date_status] == :autoverified ? :auto_verified : :needs_review

      # Añadir launch_modal al parsed_data para que el frontend lo lea correctamente
      parsed_data["launch_modal"] = ticket_status == :needs_review

      departure_datetime = if parsed_data[:flight_date].present?
        begin
          Time.zone.parse(parsed_data[:flight_date].to_s)
        rescue ArgumentError => e
          Rails.logger.warn "[ParseTicketService] Failed to parse flight_date '#{parsed_data[:flight_date]}': #{e.message}"
          nil
        end
      else
        nil
      end

      ticket.update_columns(
        flight_number: parsed_data[:flight_number],
        airline: parsed_data[:airline],
        departure_airport: parsed_data[:departure_airport],
        arrival_airport: parsed_data[:arrival_airport],
        departure_datetime: departure_datetime,
        arrival_datetime: nil,
        departure_country_id: dep_country&.id,
        arrival_country_id: arr_country&.id,
        status: ticket_status,
        parsed_data: parsed_data,
        updated_at: Time.current
      )

      ticket.reload
      confidence_level = ticket_status == :auto_verified ? :high : :medium
      return { success: true, ticket: ticket, confidence_level: confidence_level, launch_modal: ticket_status == :needs_review }
    end

    # C. INTENTO 2 - Fallback a Gemini
    begin
      raw_response = GeminiClient.parse_document(filepath, mimetype, target_year: target_year, capture_date: full_date.strftime('%Y-%m-%d'))
      parsed_data  = JSON.parse(raw_response).with_indifferent_access

      confidence_result = ConfidenceCalculatorService.call(parsed_data)

      # Persistir launch_modal en jsonb para que parse_ticket_job pueda leerlo
      parsed_data["launch_modal"] = confidence_result&.dig(:launch_modal) || false

      dep_country = Airport.find_by(iata_code: parsed_data["departure_airport"])&.country ||
                    Country.find_by(code: parsed_data["departure_country"]&.upcase)
      arr_country = Airport.find_by(iata_code: parsed_data["arrival_airport"])&.country ||
                    Country.find_by(code: parsed_data["arrival_country"]&.upcase)

      # update_columns bypasses model validations intentionally: Gemini-parsed data
      # may contain incoherent dates or missing fields — those are handled by the
      # confidence flow and the user review step, not by model guards.
      ticket.update_columns(
        flight_number:        parsed_data["flight_number"],
        airline:              parsed_data["airline"],
        departure_airport:    parsed_data["departure_airport"],
        arrival_airport:      parsed_data["arrival_airport"],
        departure_datetime:   parse_safe_datetime(parsed_data["flight_date"]),
        arrival_datetime:     nil, # Solo se rellena si el usuario lo confirma manualmente en la revisión
        departure_country_id: dep_country&.id,
        arrival_country_id:   arr_country&.id,
        status:               confidence_result[:status].to_s,
        parsed_data:          parsed_data,
        updated_at:           Time.current
      )
      ticket.reload

      { success: true, ticket: ticket, confidence_level: confidence_result[:level],
        launch_modal: confidence_result[:launch_modal] }
    end
  rescue JSON::ParserError, StandardError => e
    error_message = e.message

    # Asegurar que siempre actualizamos el ticket, incluso si hay problemas
    begin
      ticket&.update_columns(
        status: :error,
        parsed_data: { error: error_message, timestamp: Time.current.iso8601 },
        updated_at: Time.current
      )
    rescue StandardError => update_error
      Rails.logger.error "Failed to update ticket #{@ticket_id}: #{update_error.message}"
    end

    { success: false, error: error_message }
  end

  private

  def parse_safe_datetime(date_string)
    return nil unless date_string.present?
    
    begin
      Time.zone.parse(date_string.to_s)
    rescue ArgumentError => e
      Rails.logger.warn "[ParseTicketService] Failed to parse date '#{date_string}': #{e.message}"
      nil
    end
  end
end
