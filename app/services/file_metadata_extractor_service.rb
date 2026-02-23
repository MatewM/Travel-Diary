# frozen_string_literal: true
require 'exifr/jpeg'

class FileMetadataExtractorService
  def self.call(uploaded_file)
    new(uploaded_file).call
  end

  def initialize(uploaded_file)
    @uploaded_file = uploaded_file
  end

  def call
    return {} unless @uploaded_file.respond_to?(:tempfile)
    
    tempfile_path = @uploaded_file.tempfile.path
    return {} unless File.exist?(tempfile_path)

    metadata = {
      filename: @uploaded_file.original_filename,
      content_type: @uploaded_file.content_type,
      size: @uploaded_file.size
    }

    Rails.logger.info "[FileMetadataExtractor] Processing #{@uploaded_file.original_filename} (#{@uploaded_file.content_type})"
    
    # Solo intentar EXIF si es una foto real JPEG (casos raros)
    # Para screenshots usamos lastModified del JavaScript exclusivamente
    if @uploaded_file.content_type&.include?('jpeg')
      creation_time = extract_jpeg_exif_date(tempfile_path)
      
      if creation_time
        metadata[:creation_time] = creation_time.iso8601
        metadata[:creation_year] = creation_time.year
        metadata[:source] = 'exif'
        
        Rails.logger.info "[FileMetadataExtractor] ✅ EXIF date found: #{creation_time} (year: #{creation_time.year})"
      end
    end

    # Para screenshots (mayoría de casos), confiamos en lastModified del JavaScript
    Rails.logger.info "[FileMetadataExtractor] Relying on JavaScript lastModified for screenshot date"
    
    metadata
  end

  private

  def extract_jpeg_exif_date(filepath)
    exif = EXIFR::JPEG.new(filepath)
    return nil unless exif.exif?
    
    # Para fotos reales: date_time_original (cuando se tomó) > date_time (cuando se modificó)
    date = exif.date_time_original || exif.date_time
    Rails.logger.info "[FileMetadataExtractor] Found JPEG EXIF date: #{date}" if date
    date
  rescue => e
    Rails.logger.warn "[FileMetadataExtractor] JPEG EXIF extraction failed: #{e.message}"
    nil
  end
end