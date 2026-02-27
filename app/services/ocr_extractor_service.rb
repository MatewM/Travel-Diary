# frozen_string_literal: true

require "rtesseract"

class OcrExtractorService
  def self.call(filepath)
    new(filepath).call
  end

  def initialize(filepath)
    @filepath = filepath
  end

  def call
    return nil unless @filepath && File.exist?(@filepath)

    begin
      # Configuramos Tesseract con varios idiomas comunes para billetes
      image = RTesseract.new(@filepath, lang: "eng+spa+fra+deu")
      text = image.to_s
      text.presence
    rescue => e
      Rails.logger.error "OcrExtractorService: Error extracting text: #{e.message}"
      nil
    end
  end
end
