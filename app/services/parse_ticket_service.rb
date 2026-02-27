# frozen_string_literal: true

class ParseTicketService
  # Regex todoterreno para extraer año de 4 dígitos en formatos de fecha variados
  # Busca fechas como: DD/MM/YYYY, YYYY-MM-DD, DD.Mon.YYYY, etc. con variaciones de separadores
  REGEX_YEAR = /\b(?:(?:0?[1-9]|[12][0-9]|3[01])[\s\-\.\/]+(?:0?[1-9]|1[0-2]|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|ene|abr|ago|dic)[a-z]*[\s\-\.\/]+(20[1-3][0-9])|(20[1-3][0-9])[\s\-\.\/]+(?:0?[1-9]|1[0-2]|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec|ene|abr|ago|dic)[a-z]*[\s\-\.\/]+(?:0?[1-9]|[12][0-9]|3[01]))\b/i
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
      # No limpiamos el temporal aún, lo necesitamos para OCR si QR falla
    end

    if bcbp_result.present? && bcbp_result.with_indifferent_access[:source].to_s == "bcbp_barcode"
      temp_file&.unlink rescue nil
      return process_bcbp_result(ticket, bcbp_result, filepath, target_year, full_date)
    end

    # C. INTENTO 2 - PDF Texto Plano (solo si es PDF)
    best_fallback_data = nil
    best_confidence = nil

    if mimetype == "application/pdf"
      Rails.logger.info "[ParseTicketService] Attempting PDF text extraction for ticket #{@ticket_id}"
      pdf_text = PdfTextExtractorService.call(attachment.blob)
      if pdf_text.present?
        pdf_data = PdfTicketParserService.call(pdf_text, target_year: target_year, full_date: full_date)
        if pdf_data.present?
          confidence_result = ConfidenceCalculatorService.call(pdf_data)
          if confidence_result[:status] == "auto_verified"
            temp_file&.unlink rescue nil
            return update_ticket_and_return(ticket, pdf_data, confidence_result)
          end
          # Si no es auto_verified, guardamos el resultado por si OCR/Gemini fallan
          best_fallback_data = pdf_data
          best_confidence = confidence_result
        end
      end
    end

    # D. INTENTO 3 - OCR (Imagen o PDF convertido)
    Rails.logger.info "[ParseTicketService] Attempting OCR extraction for ticket #{@ticket_id}"
    ocr_text = OcrExtractorService.call(filepath)
    if ocr_text.present?
      ocr_data = OcrTicketParserService.call(ocr_text, target_year: target_year, full_date: full_date)
      if ocr_data.present?
        confidence_result = ConfidenceCalculatorService.call(ocr_data)
        if confidence_result[:status] == "auto_verified"
          temp_file&.unlink rescue nil
          return update_ticket_and_return(ticket, ocr_data, confidence_result)
        end
        
        # Si OCR es mejor que PDF (o PDF no existía), actualizamos el mejor fallback
        if best_confidence.nil? || status_priority(confidence_result[:status]) > status_priority(best_confidence[:status])
          best_fallback_data = ocr_data
          best_confidence = confidence_result
        end
      end
    end

    # E. INTENTO 4 - Fallback a Gemini (Último recurso)
    # begin
    #   raw_response = GeminiClient.parse_document(filepath, mimetype, target_year: target_year, capture_date: full_date)
    #   gemini_data  = JSON.parse(raw_response).with_indifferent_access
    #   confidence_result = ConfidenceCalculatorService.call(gemini_data)
    #   temp_file&.unlink rescue nil
    #   return update_ticket_and_return(ticket, gemini_data, confidence_result)
    # rescue => e
    #   Rails.logger.error "[ParseTicketService] Gemini fallback failed: #{e.message}"
    # end

    # Si llegamos aquí, usamos el mejor resultado obtenido (si existe) o marcamos error
    temp_file&.unlink rescue nil
    
    if best_fallback_data.present?
      return update_ticket_and_return(ticket, best_fallback_data, best_confidence)
    end

    error_message = "No se pudo extraer información válida del documento por ningún método."
    
    Rails.logger.error "[ParseTicketService] All extraction methods failed for ticket #{@ticket_id}"
    
    begin
      ticket.update_columns(
        status: 'error',
        parsed_data: { error: error_message },
        updated_at: Time.current
      )
    rescue => e
      Rails.logger.error "[ParseTicketService] Failed to update ticket #{@ticket_id}: #{e.message}"
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

  def process_bcbp_result(ticket, bcbp_result, filepath = nil, target_year = nil, full_date = nil)
    Rails.logger.info "[ParseTicketService] BCBP result is valid, processing for ticket #{@ticket_id}"
    parsed_data = bcbp_result.with_indifferent_access

    # Determinar status basado en si la fecha viene del BCBP o de metadata
    ticket_status = parsed_data[:date_status] == :autoverified ? :auto_verified : :needs_review

    # Si BCBP dice needs_review y tenemos filepath, intentar fallback OCR
    if ticket_status == :needs_review && filepath.present? && target_year.present? && full_date.present?
      Rails.logger.info "[ParseTicketService] BCBP marked needs_review, attempting OCR year fallback"
      ocr_result = try_ocr_year_fallback(ticket, filepath, parsed_data, target_year, full_date)

      if ocr_result.present?
        # Actualizar flight_date y status según OCR
        parsed_data[:flight_date] = ocr_result[:flight_date]&.iso8601
        parsed_data[:date_status] = ocr_result[:date_status]
        parsed_data[:year_warning] = ocr_result[:year_warning]
        parsed_data[:launch_modal] = ocr_result[:launch_modal]
        parsed_data[:ocr_year] = ocr_result[:ocr_year] if ocr_result[:ocr_year]
        parsed_data[:selected_year] = ocr_result[:selected_year] if ocr_result[:selected_year]

        ticket_status = ocr_result[:date_status] == :autoverified ? :auto_verified : :needs_review
      else
        parsed_data["launch_modal"] = false
      end
    else
      parsed_data["launch_modal"] = false
    end

    # Buscar países por IATA usando los aeropuertos
    dep_country = Airport.find_by(iata_code: parsed_data[:departure_airport])&.country
    arr_country = Airport.find_by(iata_code: parsed_data[:arrival_airport])&.country

    departure_datetime = if parsed_data[:flight_date].present?
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
    { success: true, ticket: ticket, confidence_level: confidence_level, launch_modal: ticket_status == :needs_review && parsed_data["launch_modal"] == true }
  end

  def update_ticket_and_return(ticket, parsed_data, confidence_result)
    # Persistir launch_modal en jsonb para que parse_ticket_job pueda leerlo
    parsed_data["launch_modal"] = confidence_result&.dig(:launch_modal) || false

    dep_country = Airport.find_by(iata_code: parsed_data["departure_airport"])&.country ||
                  Country.find_by(code: parsed_data["departure_country"]&.upcase)
    arr_country = Airport.find_by(iata_code: parsed_data["arrival_airport"])&.country ||
                  Country.find_by(code: parsed_data["arrival_country"]&.upcase)

    ticket.update_columns(
      flight_number:        parsed_data["flight_number"],
      airline:              parsed_data["airline"],
      departure_airport:    parsed_data["departure_airport"],
      arrival_airport:      parsed_data["arrival_airport"],
      departure_datetime:   normalize_datetime(parsed_data["flight_date"]),
      arrival_datetime:     nil,
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

  def status_priority(status)
    case status.to_s
    when "auto_verified" then 3
    when "needs_review" then 2
    when "manual_required" then 1
    else 0
    end
  end

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

  def extract_year_from_ocr(ocr_text)
    return nil if ocr_text.blank?

    match = ocr_text.match(REGEX_YEAR)
    return nil unless match

    # Buscar en los grupos capturados (pueden estar en diferentes posiciones)
    year_str = match.to_a.find { |m| m&.match?(/\d{4}/) && m.to_i.between?(2010, 2039) }
    return nil unless year_str

    year_str.to_i
  rescue => e
    Rails.logger.warn "[ParseTicketService] Error extracting year from OCR: #{e.message}"
    nil
  end

  def try_ocr_year_fallback(ticket, filepath, bcbp_data, target_year, full_date)
    return nil unless bcbp_data.present? && bcbp_data[:julian_day].present?

    Rails.logger.info "[ParseTicketService] Attempting OCR year fallback for ticket #{@ticket_id}"
    ocr_text = OcrExtractorService.call(filepath)
    return nil unless ocr_text.present?

    ocr_year = extract_year_from_ocr(ocr_text)
    return nil unless ocr_year

    # Leer el año seleccionado en el dashboard
    selected_year = ticket.original_file_metadata&.dig("selected_year")&.to_i || target_year

    Rails.logger.info "[ParseTicketService] OCR detected year #{ocr_year}, selected_year #{selected_year}"

    # Recalcular flight_date con el año detectado por OCR
    flight_date = Date.ordinal(ocr_year, bcbp_data[:julian_day]) rescue nil
    return nil unless flight_date

    # Comparar años
    if ocr_year == selected_year
      # Años coinciden: cambiar a autoverified
      Rails.logger.info "[ParseTicketService] OCR year matches selected_year, marking as autoverified"
      {
        flight_date: flight_date,
        date_status: :autoverified,
        launch_modal: false,
        year_warning: false
      }
    else
      # Años no coinciden: mantener needs_review con aviso
      Rails.logger.warn "[ParseTicketService] OCR year #{ocr_year} differs from selected_year #{selected_year}"
      {
        flight_date: flight_date,
        date_status: :needs_review,
        launch_modal: true,
        year_warning: true,
        ocr_year: ocr_year,
        selected_year: selected_year
      }
    end
  end
end
