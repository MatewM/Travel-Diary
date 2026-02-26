# frozen_string_literal: true

class ParseTicketService
  # Interfaz pública: ya NO acepta capture_date desde fuera.
  # El servicio lo calcula internamente.
  def self.call(ticket_id)
    new(ticket_id).call
  rescue StandardError => e
    Rails.logger.error "ParseTicketService: Unexpected error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    { success: false, error: "Unexpected error: #{e.message}" }
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

    # Preparar el archivo según su tipo
    mimetype = attachment.content_type
    temp_file = nil
    if mimetype.start_with?("image/")
      # Para imágenes, usar el path directo sin conversión
      filepath = ActiveStorage::Blob.service.path_for(attachment.blob.key)
    elsif mimetype == "application/pdf"
      # Para PDFs, convertir primera página a PNG temporal con crop al 40% superior
      temp_file = convert_pdf_to_cropped_image(attachment.blob)
      if temp_file
        filepath = temp_file.path
      else
        # Fallback: usar PDF original si falla la conversión
        filepath = ActiveStorage::Blob.service.path_for(attachment.blob.key)
      end
    else
      # Tipo no soportado, usar path directo (fallback)
      filepath = ActiveStorage::Blob.service.path_for(attachment.blob.key)
    end

    # Extraer fecha usando ticket.created_at como base robusta
    extraction_result = ExifYearExtractorService.call(ticket)

    full_date = extraction_result[:full_date]
    target_year = extraction_result[:year]
    Rails.logger.info "[ParseTicketService] Using ticket creation date=#{full_date}, target_year=#{target_year} for ticket #{@ticket_id}"

    # B. INTENTO 1 - Vía Barcode/QR
    begin
      bcbp_result = BarcodeExtractorService.call(filepath, full_date.strftime('%Y-%m-%d'))
      Rails.logger.info "[ParseTicketService] BarcodeExtractorService.call result for ticket #{@ticket_id}: #{bcbp_result.inspect}"
    ensure
      # Limpiar archivo temporal si fue creado para PDF
      temp_file&.unlink rescue nil
    end

    if bcbp_result.present? && bcbp_result.with_indifferent_access[:source].to_s == "bcbp_barcode"
      Rails.logger.info "[ParseTicketService] BCBP result is valid, processing for ticket #{@ticket_id}"
      parsed_data = bcbp_result.with_indifferent_access

      # Buscar países por IATA usando los aeropuertos
      dep_country = Airport.find_by(iata_code: parsed_data[:departure_airport])&.country
      arr_country = Airport.find_by(iata_code: parsed_data[:arrival_airport])&.country

      # Determinar status basado en si la fecha viene del BCBP o de metadata
      ticket_status = parsed_data[:date_status] == :autoverified ? :auto_verified : :needs_review

      # Añadir launch_modal al parsed_data para que el frontend lo lea correctamente
      # El usuario ha solicitado que para :needs_review NO se lance el modal automáticamente.
      parsed_data["launch_modal"] = false


      departure_datetime = if parsed_data[:flight_date].present?
        # Asegúrate de usar Time.zone.parse para convertir el String en objeto Time
        Time.zone.parse(parsed_data[:flight_date].to_s) 
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

    Rails.logger.warn "[ParseTicketService] BCBP result failed validation for ticket #{@ticket_id}. bcbp_result: #{bcbp_result.inspect}"
    
    # C. INTENTO 2 - Fallback a Gemini (COMENTADO: Solo permitir QR codes con librería local)
    # begin
    #   raw_response = GeminiClient.parse_document(filepath, mimetype, target_year: target_year, capture_date: full_date)
    #   parsed_data  = JSON.parse(raw_response).with_indifferent_access

    #   confidence_result = ConfidenceCalculatorService.call(parsed_data)

    #   # Persistir launch_modal en jsonb para que parse_ticket_job pueda leerlo
    #   parsed_data["launch_modal"] = confidence_result&.dig(:launch_modal) || false

    #   dep_country = Airport.find_by(iata_code: parsed_data["departure_airport"])&.country ||
    #                 Country.find_by(code: parsed_data["departure_country"]&.upcase)
    #   arr_country = Airport.find_by(iata_code: parsed_data["arrival_airport"])&.country ||
    #                 Country.find_by(code: parsed_data["arrival_country"]&.upcase)

    #   # update_columns bypasses model validations intentionally: Gemini-parsed data
    #   # may contain incoherent dates or missing fields — those are handled by the
    #   # confidence flow and the user review step, not by model guards.
    #   ticket.update_columns(
    #     flight_number:        parsed_data["flight_number"],
    #     airline:              parsed_data["airline"],
    #     departure_airport:    parsed_data["departure_airport"],
    #     arrival_airport:      parsed_data["arrival_airport"],
    #     departure_datetime:   normalize_datetime(parsed_data["flight_date"]),
    #     arrival_datetime:     nil, # Solo se rellena si el usuario lo confirma manualmente en la revisión
    #     departure_country_id: dep_country&.id,
    #     arrival_country_id:   arr_country&.id,
    #     status:               confidence_result[:status].to_s,
    #     parsed_data:          parsed_data,
    #     updated_at:           Time.current
    #   )
    #   ticket.reload

    #   { success: true, ticket: ticket, confidence_level: confidence_result[:level],
    #     launch_modal: confidence_result[:launch_modal] }
    # end
    # Si llegamos aquí es porque BarcodeExtractorService retornó nil y Gemini está desactivado
    error_message = "No se detectó ningún código QR o de barras legible en el documento."
    
    Rails.logger.error "[ParseTicketService] No QR detected, updating ticket #{@ticket_id} to error status"
    
    begin
      update_result = ticket.update_columns(
        status: 'error',
        parsed_data: { error: error_message },
        updated_at: Time.current
      )
      Rails.logger.info "[ParseTicketService] Ticket #{@ticket_id} update_columns result: #{update_result}"
      Rails.logger.info "[ParseTicketService] Ticket #{@ticket_id} status after update: #{ticket.reload.status}"
    rescue => e
      Rails.logger.error "[ParseTicketService] Failed to update ticket #{@ticket_id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
    
    return { success: false, error: error_message }

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

  def convert_pdf_to_cropped_image(blob)
    require "mini_magick"

    pdf_path = ActiveStorage::Blob.service.path_for(blob.key)
    temp_image = Tempfile.new(["pdf_page", ".png"])
    temp_image.close

    begin
      # Convertir primera página del PDF a PNG
      img = MiniMagick::Image.open("#{pdf_path}[0]") # [0] indica primera página
      img.format "png"

      # Aplicar crop al 40% superior para evitar QR publicitarios
      width = img.width
      height = img.height
      crop_height = (height * 0.4).to_i

      img.crop "#{width}x#{crop_height}+0+0"
      img.write temp_image.path

      temp_image
    rescue => e
      Rails.logger.error "ParseTicketService: PDF conversion failed: #{e.message}"
      temp_image.unlink rescue nil
      # Fallback: devolver nil para usar el PDF original
      nil
    end
  end

  def normalize_datetime(value)
    return nil if value.blank?
    return value if value.is_a?(Time) || value.is_a?(DateTime) ||
                    value.is_a?(ActiveSupport::TimeWithZone)
    return value.to_time if value.is_a?(Date)
    return nil unless value.is_a?(String)
    begin
      Time.zone.parse(value)
    rescue ArgumentError, TypeError
      begin
        DateTime.parse(value).in_time_zone
      rescue ArgumentError, TypeError
        Rails.logger.warn "ParseTicketService: Cannot parse datetime: #{value.inspect}"
        nil
      end
    end
  end
end
