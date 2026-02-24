# frozen_string_literal: true

gem 'zxing_cpp'  # activa la gema explícitamente en el load path
require 'zxing'
require 'uri'
require 'cgi'

class BarcodeExtractorService
  def self.call(filepath, capture_date:)
    begin
      return nil if filepath.nil? || !File.exist?(filepath)

      # Try different approaches for ZXing.decode
      raw_string = nil
      begin
        # First try: direct file path
        raw_string = ZXing.decode(filepath.to_s)
      rescue => e1
        Rails.logger.warn "BarcodeExtractor direct path failed: #{e1.message}"
        begin
          # Second try: file:// URI
          file_uri = "file://#{filepath}"
          raw_string = ZXing.decode(file_uri)
        rescue => e2
          Rails.logger.warn "BarcodeExtractor file URI failed: #{e2.message}"
          # Third try: URI encoded
          encoded_path = "file://#{CGI.escape(filepath)}"
          raw_string = ZXing.decode(encoded_path)
        end
      end

      return nil if raw_string.nil? || raw_string.blank?

      result = BcbpParserService.process_decoded_string(raw_string, capture_date)

      # Retornar datos BCBP si se pudo parsear, incluyendo el date_status
      # para que ParseTicketService determine si es autoverified o needs_review
      if result
          final_result = {
          source: :bcbp, # <--- AÑADIR ESTA LÍNEA
          flight_number: result[:flight_number],
          airline: result[:airline],
          departure_airport: result[:departure_airport],
          arrival_airport: result[:arrival_airport],
          flight_date: result[:flight_date]&.iso8601,
          date_status: result[:date_status]
        }
      else
        nil
      end
    rescue => e
      Rails.logger.error "BarcodeExtractorService failed for #{filepath}: #{e.message}"
      nil
    end
  end
end