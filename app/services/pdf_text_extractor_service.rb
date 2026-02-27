# frozen_string_literal: true

require "pdf-reader"

class PdfTextExtractorService
  def self.call(blob)
    new(blob).call
  end

  def initialize(blob)
    @blob = blob
  end

  def call
    temp_file = Tempfile.new(["ticket", ".pdf"])
    temp_file.binmode
    temp_file.write(@blob.download)
    temp_file.rewind

    begin
      reader = PDF::Reader.new(temp_file.path)
      # Solo extraemos las primeras 2 páginas para eficiencia
      text = reader.pages[0..1].map(&:text).join("\n")
      text.presence
    rescue => e
      Rails.logger.error "PdfTextExtractorService: Error extracting text: #{e.message}"
      nil
    ensure
      temp_file.close
      temp_file.unlink
    end
  end
end
