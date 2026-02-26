# frozen_string_literal: true

require 'zxing'
require "uri"
require "cgi"
class BarcodeExtractorService
  def self.call(filepath, capturedate)
    Rails.logger.info "BarcodeExtractorService: Starting for #{filepath}"
    return nil if filepath.nil? || !File.exist?(filepath)

    # Timeout de 30 segundos para evitar que se cuelgue
    Timeout.timeout(30) do
      # Intentamos decodificar directamente (si es PDF, ParseTicketService ya lo envió recortado)
      raw_string = attempt_decode(filepath)

      if raw_string.present?
        parse_and_return(raw_string, capturedate)
      else
        Rails.logger.warn "BarcodeExtractorService: No QR/barcode found after attempts"
        nil
      end
    end
  rescue Timeout::Error
    Rails.logger.error "BarcodeExtractorService: TIMEOUT after 30 seconds"
    nil
  rescue => e
    Rails.logger.error "BarcodeExtractorService: FAILED #{e.message}"
    nil
  end

  private_class_method def self.attempt_decode(filepath)
    processed_path = nil
    Rails.logger.info "BarcodeExtractorService: Starting attempt_decode for #{filepath}"

    # Intentos 1 y 2: Motores originales
    Rails.logger.info "BarcodeExtractorService: [1] Trying ZXing on original image..."
  # Attempt 1: ZXing-CPP (soporta QR Code, PDF417, Aztec, DataMatrix)
  begin
    results = ZXing.decode(filepath.to_s)
    if results.present? && !results.empty?
      result = results.first.text
      Rails.logger.info "BarcodeExtractorService: 1 ZXingCPP SUCCESS. Raw #{result.to_s.gsub(/\s/, ' ')[0..79]}"
        return result
      else
        Rails.logger.info "BarcodeExtractorService: [1] ZXing found nothing on original"
      end
    end rescue Rails.logger.warn "BarcodeExtractorService: [1] ZXing timeout on original image"

    Rails.logger.info "BarcodeExtractorService: [2] Trying ZBar on original image..."
    result = zbar_decode(filepath)
    if result.present?
      Rails.logger.info "BarcodeExtractorService: [2] ZBar SUCCESS on original: #{result[0..100]}..."
      return result
    else
      Rails.logger.info "BarcodeExtractorService: [2] ZBar found nothing on original"
    end

    # Intentos 3 y 4: Con preprocesamiento (filtros de imagen)
    Rails.logger.info "BarcodeExtractorService: [3-4] Trying with image preprocessing..."
    begin
      processed_path = preprocess_image(filepath)
      if processed_path
        Rails.logger.info "BarcodeExtractorService: [3] Trying ZXing on processed image..."
        Timeout.timeout(5) do
          result = ZXing.decode(processed_path) rescue nil
          if result.present?
            Rails.logger.info "BarcodeExtractorService: [3] ZXing SUCCESS on processed: #{result[0..100]}..."
            return result
          else
            Rails.logger.info "BarcodeExtractorService: [3] ZXing found nothing on processed"
          end
        end rescue Rails.logger.warn "BarcodeExtractorService: [3] ZXing timeout on processed image"

        Rails.logger.info "BarcodeExtractorService: [4] Trying ZBar on processed image..."
        result = zbar_decode(processed_path)
        if result.present?
          Rails.logger.info "BarcodeExtractorService: [4] ZBar SUCCESS on processed: #{result[0..100]}..."
          return result
        else
          Rails.logger.info "BarcodeExtractorService: [4] ZBar found nothing on processed"
        end
      else
        Rails.logger.warn "BarcodeExtractorService: Preprocessing failed, skipping attempts 3-4"
      end
    ensure
      File.delete(processed_path) if processed_path && File.exist?(processed_path)
    end

    Rails.logger.info "BarcodeExtractorService: All attempts failed"
    nil
  end

  private_class_method def self.zbar_decode(filepath)
    # Timeout de 10 segundos para zbarimg
    Timeout.timeout(10) do
      out = `zbarimg --raw -q "#{filepath}" 2>/dev/null`.strip
      out.presence
    end
  rescue Timeout::Error
    Rails.logger.warn "BarcodeExtractorService: ZBar CLI timeout after 10 seconds"
    nil
  rescue => e
    Rails.logger.warn "BarcodeExtractorService ZBar CLI failed: #{e.message}"
    nil
  end

  private_class_method def self.preprocess_image(filepath)
    require "mini_magick"
    processed = Tempfile.new([ "barcode_processed", ".png" ])
    processed.close

    Timeout.timeout(40) do
      img = MiniMagick::Image.open(filepath)

      img.combine_options do |c|
        # 1. Resize moderado: 150% o 200% es suficiente para capturas.
        c.resize "200%"

        # 2. Gris: Fundamental para eliminar el azul de Ryanair/Volaris.
        c.colorspace "Gray"

        # 3. Mejora de definición sin inventar píxeles:
        c.contrast
        c.normalize

        # 4. Threshold equilibrado: 50% es el estándar para separar blanco de negro puro.
        # El 40% que usas puede hacer que el gris oscuro se vuelva blanco erróneamente.
        c.threshold "50%"

        # 5. Sharpen suave: 0x3 es muy fuerte, 0x1 es suficiente para definir bordes.
        c.sharpen "0x1"
      end

      img.write(processed.path)
      Rails.logger.info "BarcodeExtractorService: Preprocessed (200% resize, 50% threshold) at #{processed.path}"
      processed.path
    end
  rescue Timeout::Error
    Rails.logger.warn "BarcodeExtractorService: MiniMagick preprocess timeout after 40 seconds"
    File.delete(processed.path) if File.exist?(processed.path)
    nil
  rescue => e
    Rails.logger.warn "BarcodeExtractorService: MiniMagick preprocess failed: #{e.message}"
    File.delete(processed.path) if File.exist?(processed.path)
    nil
  end

  private_class_method def self.parse_and_return(raw_string, capturedate)
    Rails.logger.info "BarcodeExtractorService: Decoded #{raw_string[0..60]}..."
    result = BcbpParserService.process_decoded_string(raw_string, capturedate)
    unless result
      Rails.logger.info "BarcodeExtractorService: decoded but parse failed. Raw: #{raw_string.to_s.gsub("\n", "\\n")[0..79]}"
      return nil
    end

    {
      source:            :bcbp,
      flight_number:     result[:flight_number],
      airline:           result[:airline],
      departure_airport: result[:departure_airport],
      arrival_airport:   result[:arrival_airport],
      flight_date:       result[:flight_date]&.iso8601,
      date_status:       result[:date_status]
    }
  rescue => e
    Rails.logger.warn "BarcodeExtractorService: BCBP parse failed: #{e.message}"
    Rails.logger.info "BarcodeExtractorService: decoded but parse failed. Raw: #{raw_string.to_s.gsub("\n", "\\n")[0..79]}"
    nil
  end
end
