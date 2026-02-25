# frozen_string_literal: true

require "zxing"
require "uri"
require "cgi"
class BarcodeExtractorService
  def self.call(filepath, capturedate)
    Rails.logger.info "BarcodeExtractorService: Starting for #{filepath}"
    return nil if filepath.nil? || !File.exist?(filepath)
    Rails.logger.info "BarcodeExtractorService: File exists, #{File.size(filepath)} bytes"

    cropped_path = BarcodeRegionCropper.crop_top_region(filepath) rescue nil

    raw_string =
      if cropped_path && File.exist?(cropped_path)
        attempt_decode(cropped_path) || attempt_decode(filepath)
      else
        attempt_decode(filepath)
      end

    if raw_string.present?
      parse_and_return(raw_string, capturedate)
    else
      Rails.logger.warn "BarcodeExtractorService: No QR/barcode found after all 4 attempts"
      nil
    end
  rescue => e
    Rails.logger.error "BarcodeExtractorService: FAILED #{e.message}"
    Rails.logger.error e.backtrace.first(3).join("\n")
    nil
  ensure
    File.delete(cropped_path) if cropped_path && File.exist?(cropped_path)
  end

  private_class_method def self.attempt_decode(filepath)
    processed_path = nil

    # Attempt 1: ZXing with original image
    begin
      result = ZXing.decode(filepath.to_s)
      if result.present?
        Rails.logger.info "BarcodeExtractorService: [1] ZXing original SUCCESS. Raw: #{result.gsub("\n", "\\n")[0..79]}"
        return result
      end
    rescue StandardError => e
      Rails.logger.warn "BarcodeExtractorService: [1] ZXing original failed: #{e.message}"
    end

    # Attempt 2: ZBar with original image
    begin
      result = zbar_decode(filepath)
      if result.present?
        Rails.logger.info "BarcodeExtractorService: [2] ZBar original SUCCESS. Raw: #{result.to_s.gsub("\n", "\\n")[0..79]}"
        return result
      end
    rescue => e
      Rails.logger.warn "BarcodeExtractorService: [2] ZBar original failed: #{e.message}"
    end

    # Attempts 3+4: MiniMagick preprocess then ZXing + ZBar
    begin
      processed_path = preprocess_image(filepath)
      if processed_path
        begin
          result = ZXing.decode(processed_path)
          if result.present?
            Rails.logger.info "BarcodeExtractorService: [3] ZXing processed SUCCESS. Raw: #{result.gsub("\n", "\\n")[0..79]}"
            return result
          end
        rescue StandardError => e
          Rails.logger.warn "BarcodeExtractorService: [3] ZXing processed failed: #{e.message}"
        end

        begin
          result = zbar_decode(processed_path)
          if result.present?
            Rails.logger.info "BarcodeExtractorService: [4] ZBar processed SUCCESS. Raw: #{result.to_s.gsub("\n", "\\n")[0..79]}"
            return result
          end
        rescue => e
          Rails.logger.warn "BarcodeExtractorService: [4] ZBar processed failed: #{e.message}"
        end
      end
    rescue => e
      Rails.logger.warn "BarcodeExtractorService: MiniMagick preprocess failed: #{e.message}"
    ensure
      File.delete(processed_path) if processed_path && File.exist?(processed_path)
    end

    nil
  end

  private_class_method def self.zbar_decode(filepath)
    out = `zbarimg --raw -q "#{filepath}" 2>/dev/null`.strip
    out.presence
  rescue => e
    Rails.logger.warn "BarcodeExtractorService ZBar CLI failed: #{e.message}"
    nil
  end

  private_class_method def self.preprocess_image(filepath)
    require "mini_magick"
    processed = Tempfile.new([ "barcode_processed", ".png" ])
    processed.close

    img = MiniMagick::Image.open(filepath)
    # Preprocesamiento agresivo para códigos QR pequeños
    img.resize "400%"        # Ampliación extrema para QR pequeños
    img.colorspace "Gray"    # Conversión a escala de grises
    img.contrast             # Aumento de contraste
    img.normalize            # Normalización
    img.threshold "25%"      # Threshold más bajo para códigos pequeños
    img.sharpen "0x3"        # Sharpening más fuerte
    img.write(processed.path)

    Rails.logger.info "BarcodeExtractorService: Preprocessed image (400% resize, threshold 40%) at #{processed.path}"
    processed.path
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
      flight_date:       result[:flight_date].iso8601,
      date_status:       result[:date_status]
    }
  rescue => e
    Rails.logger.warn "BarcodeExtractorService: BCBP parse failed: #{e.message}"
    Rails.logger.info "BarcodeExtractorService: decoded but parse failed. Raw: #{raw_string.to_s.gsub("\n", "\\n")[0..79]}"
    nil
  end
end
