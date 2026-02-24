# frozen_string_literal: true

gem 'zxing_cpp'  # activa la gema explícitamente en el load path
require 'zxing'
require 'uri'
require 'cgi'

class BarcodeExtractorService
  def self.call(filepath, capture_date:)
    Rails.logger.info "[BarcodeExtractorService] Starting for #{filepath}"
    
    begin
      return nil if filepath.nil? || !File.exist?(filepath)
      Rails.logger.info "[BarcodeExtractorService] File exists, size: #{File.size(filepath)} bytes"

      # Try different approaches for ZXing.decode
      raw_string = nil
      begin
        # First try: direct file path
        Rails.logger.info "[BarcodeExtractorService] Trying direct decode..."
        raw_string = ZXing.decode(filepath.to_s)
        Rails.logger.info "[BarcodeExtractorService] Direct decode SUCCESS: #{raw_string&.length} chars"
      rescue => e1
        Rails.logger.warn "[BarcodeExtractorService] Direct path failed: #{e1.message}"
        begin
          # Second try: file:// URI
          file_uri = "file://#{filepath}"
          Rails.logger.info "[BarcodeExtractorService] Trying file URI: #{file_uri}"
          raw_string = ZXing.decode(file_uri)
          Rails.logger.info "[BarcodeExtractorService] File URI SUCCESS: #{raw_string&.length} chars"
        rescue => e2
          Rails.logger.warn "[BarcodeExtractorService] File URI failed: #{e2.message}"
          # Third try: URI encoded
          encoded_path = "file://#{CGI.escape(filepath)}"
          Rails.logger.info "[BarcodeExtractorService] Trying encoded: #{encoded_path}"
          raw_string = ZXing.decode(encoded_path)
          Rails.logger.info "[BarcodeExtractorService] Encoded SUCCESS: #{raw_string&.length} chars"
        end
      end

      if raw_string.nil? || raw_string.blank?
        Rails.logger.warn "[BarcodeExtractorService] No QR/barcode found in image"
        return nil
      end

      Rails.logger.info "[BarcodeExtractorService] Decoded string: #{raw_string[0..60]}..."

      result = BcbpParserService.process_decoded_string(raw_string, capture_date)
      Rails.logger.info "[BarcodeExtractorService] BCBP parser result: #{result.inspect}"

      # Retornar datos BCBP si se pudo parsear, incluyendo el date_status
      # para que ParseTicketService determine si es autoverified o needs_review
      if result
        final_result = {
          source: :bcbp,
          flight_number: result[:flight_number],
          airline: result[:airline],
          departure_airport: result[:departure_airport],
          arrival_airport: result[:arrival_airport],
          flight_date: result[:flight_date]&.iso8601,
          date_status: result[:date_status]
        }
        Rails.logger.info "[BarcodeExtractorService] Returning final result: #{final_result.inspect}"
        final_result
      else
        Rails.logger.warn "[BarcodeExtractorService] BCBP parser returned nil - not a valid boarding pass"
        nil
      end
    rescue => e
      Rails.logger.error "[BarcodeExtractorService] FAILED for #{filepath}: #{e.message}"
      Rails.logger.error "[BarcodeExtractorService] Backtrace: #{e.backtrace.first(3).join("\n")}"
      nil
    end
  end
end