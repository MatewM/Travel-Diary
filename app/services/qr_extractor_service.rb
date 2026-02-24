# frozen_string_literal: true

gem 'zxing_cpp'  # activa la gema explícitamente en el load path
require 'zxing'
require 'uri'
require 'cgi'

class QrExtractorService
  def self.call(filepath, capture_date: nil)
    begin
      return nil if filepath.nil? || !File.exist?(filepath)
      return nil unless filepath.match?(/\.(jpg|jpeg|png)$/i)

      # Try different approaches for ZXing.decode
      begin
        # First try: direct file path
        raw_string = ZXing.decode(filepath.to_s)
      rescue => e1
        Rails.logger.warn "Direct path failed: #{e1.message}"
        begin
          # Second try: file:// URI
          file_uri = "file://#{filepath}"
          raw_string = ZXing.decode(file_uri)
        rescue => e2
          Rails.logger.warn "File URI failed: #{e2.message}"
          # Third try: URI encoded
          encoded_path = "file://#{CGI.escape(filepath)}"
          raw_string = ZXing.decode(encoded_path)
        end
      end
      return nil if raw_string.nil? || raw_string.blank?

      BcbpParserService.process_decoded_string(raw_string, capture_date)
    rescue => e
      Rails.logger.warn "QrExtractorService failed for #{filepath}: #{e.message}"
      nil
    end
  end
end