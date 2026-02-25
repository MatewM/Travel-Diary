# frozen_string_literal: true
require "zxing"
require "uri"
require "cgi"
require "zbar"
class BarcodeExtractorService
  def self.call(filepath, capturedate)
    Rails.logger.info "BarcodeExtractorService: Starting for #{filepath}"
    return nil if filepath.nil? || !File.exist?(filepath)
    Rails.logger.info "BarcodeExtractorService: File exists, #{File.size(filepath)} bytes"

    raw_string = attempt_decode(filepath)

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
  end

  private_class_method def self.attempt_decode(filepath)
    processed_path = nil

    # Attempt 1: ZXing with original image
    begin
      result = ZXing.decode(filepath.to_s)
      Rails.logger.info "BarcodeExtractorService: [1] ZXing original SUCCESS"
      return result if result.present?
    rescue => e
      Rails.logger.warn "BarcodeExtractorService: [1] ZXing original failed: #{e.message}"
    end

    # Attempt 2: ZBar with original image
    begin
      result = zbar_decode(filepath)
      Rails.logger.info "BarcodeExtractorService: [2] ZBar original SUCCESS"
      return result if result.present?
    rescue => e
      Rails.logger.warn "BarcodeExtractorService: [2] ZBar original failed: #{e.message}"
    end

    # Attempts 3+4: MiniMagick preprocess then ZXing + ZBar
    begin
      processed_path = preprocess_image(filepath)
      if processed_path
        begin
          result = ZXing.decode(processed_path)
          Rails.logger.info "BarcodeExtractorService: [3] ZXing processed SUCCESS"
          return result if result.present?
        rescue => e
          Rails.logger.warn "BarcodeExtractorService: [3] ZXing processed failed: #{e.message}"
        end

        begin
          result = zbar_decode(processed_path)
          Rails.logger.info "BarcodeExtractorService: [4] ZBar processed SUCCESS"
          return result if result.present?
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
    require "zbar"
    image = ZBar::Image.from_file(filepath.to_s)
    results = image.process
    results.first&.data
  end

  private_class_method def self.preprocess_image(filepath)
    require "mini_magick"
    processed = Tempfile.new(["barcode_processed", ".png"])
    processed.close

    img = MiniMagick::Image.open(filepath)
    img.resize "300%"
    img.colorspace "Gray"
    img.threshold "45%"
    img.sharpen "0x2"
    img.write(processed.path)

    Rails.logger.info "BarcodeExtractorService: Preprocessed image at #{processed.path}"
    processed.path
  end

  private_class_method def self.parse_and_return(raw_string, capturedate)
    Rails.logger.info "BarcodeExtractorService: Decoded #{raw_string[0..60]}..."
    result = BcbpParserService.process_decoded_string(raw_string, capturedate)
    return nil unless result

    {
      flight_number:     result[:flight_number],
      airline:           result[:airline],
      departure_airport: result[:departure_airport],
      arrival_airport:   result[:arrival_airport],
      flight_date:       result[:flight_date].iso8601,
      date_status:       result[:date_status]
    }
  rescue => e
    Rails.logger.warn "BarcodeExtractorService: BCBP parse failed: #{e.message}"
    nil
  end
end
