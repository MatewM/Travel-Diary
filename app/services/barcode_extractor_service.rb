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
    Timeout.timeout(5) do
      result = ZXing.decode(filepath.to_s) rescue nil
      if result.present?
        Rails.logger.info "BarcodeExtractorService: [1] ZXing SUCCESS on original: #{result[0..100]}..."
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

    Timeout.timeout(10) do
      img = MiniMagick::Image.open(filepath)
      # Preprocesamiento agresivo para códigos QR pequeños
      img.resize "200%"        # Ampliación extrema para QR pequeños
      img.colorspace "Gray"    # Conversión a escala de grises
      img.contrast             # Aumento de contraste
      img.normalize            # Normalización
      img.threshold "25%"      # Threshold más bajo para códigos pequeños
      img.sharpen "0x3"        # Sharpening más fuerte
      img.write(processed.path)

      Rails.logger.info "BarcodeExtractorService: Preprocessed image (400% resize, threshold 40%) at #{processed.path}"
      processed.path
    end
  rescue Timeout::Error
    Rails.logger.warn "BarcodeExtractorService: MiniMagick preprocess timeout after 10 seconds"
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
