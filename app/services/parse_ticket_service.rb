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

    # Extraer año desde EXIF o metadatos originales
    target_year = ExifYearExtractorService.call(
      filepath, 
      mimetype, 
      original_metadata: ticket.original_file_metadata
    )
    
    if target_year
      Rails.logger.info "[ParseTicketService] Using EXIF target_year=#{target_year} for ticket #{@ticket_id}"
      raw_response = GeminiClient.parse_document(filepath, mimetype, target_year: target_year)
    else
      Rails.logger.info "[ParseTicketService] No EXIF year found, letting Gemini infer for ticket #{@ticket_id}"
      raw_response = GeminiClient.parse_document(filepath, mimetype)
    end
    parsed_data  = JSON.parse(raw_response)

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
      departure_datetime:   parsed_data["flight_date"].present? ? Time.zone.parse(parsed_data["flight_date"]) : nil,
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
end
