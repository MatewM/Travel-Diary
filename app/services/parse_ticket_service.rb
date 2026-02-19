# frozen_string_literal: true

class ParseTicketService
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

    # path_for works with disk storage (development/test).
    # In production with S3, the job downloads the blob to a tempfile first.
    file_path  = ActiveStorage::Blob.service.path_for(attachment.blob.key)
    mime_type  = attachment.content_type

    raw_response = GeminiClient.parse_document(file_path, mime_type)
    parsed_data  = JSON.parse(raw_response)

    confidence_result = ConfidenceCalculatorService.call(parsed_data)

    dep_country = Airport.find_by(iata_code: parsed_data["departure_airport"])&.country
    arr_country = Airport.find_by(iata_code: parsed_data["arrival_airport"])&.country

    # update_columns bypasses model validations intentionally: Gemini-parsed data
    # may contain incoherent dates or missing fields — those are handled by the
    # confidence flow and the user review step, not by model guards.
    ticket.update_columns(
      flight_number:        parsed_data["flight_number"],
      airline:              parsed_data["airline"],
      departure_airport:    parsed_data["departure_airport"],
      arrival_airport:      parsed_data["arrival_airport"],
      departure_datetime:   parsed_data["departure_datetime"],
      arrival_datetime:     parsed_data["arrival_datetime"],
      departure_country_id: dep_country&.id,
      arrival_country_id:   arr_country&.id,
      status:               confidence_result[:status].to_s,
      parsed_data:          parsed_data,
      updated_at:           Time.current
    )
    ticket.reload

    { success: true, ticket: ticket, confidence_level: confidence_result[:level] }
  rescue JSON::ParserError, StandardError => e
    ticket&.update_columns(
      status:     "error",
      parsed_data: { error: e.message },
      updated_at: Time.current
    )
    { success: false, error: e.message }
  end
end
