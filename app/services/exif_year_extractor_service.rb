# frozen_string_literal: true
require 'exifr/jpeg'

class ExifYearExtractorService
  def self.call(filepath, mimetype, original_metadata: nil)
    new(filepath, mimetype, original_metadata).call
  end

  def initialize(filepath, mimetype, original_metadata)
    @filepath = filepath
    @mimetype = mimetype
    @original_metadata = original_metadata
  end

  def call
    # Primero intentar EXIF (solo para fotos reales)
    year = extract_from_exif if jpeg?
    
    if year
      Rails.logger.info "[ExifYearExtractor] Found EXIF year: #{year}"
      return year.to_s
    end
    
    # Si no hay EXIF, usar metadatos originales guardados (screenshots, PDFs, etc.)
    year = extract_from_original_metadata
    if year
      Rails.logger.info "[ExifYearExtractor] Found original metadata year: #{year}"
      return year.to_s
    end
    
    # Fallback: usar metadatos del archivo procesado
    year = extract_from_file_metadata
    if year
      Rails.logger.info "[ExifYearExtractor] Found processed file metadata year: #{year}"
      return year.to_s
    end
    
    Rails.logger.info "[ExifYearExtractor] No metadata found"
    nil
  end

  private

  def jpeg?
    @mimetype.to_s.include?('jpeg') || @mimetype.to_s.include?('jpg')
  end

  def extract_from_exif
    exif = EXIFR::JPEG.new(@filepath)
    return nil unless exif.exif?
    # Usamos date_time_original (cuando se tomó la foto), NO date_time (cuando se modificó)
    date = exif.date_time_original || exif.date_time
    date&.year
  rescue => e
    Rails.logger.warn "[ExifYearExtractor] EXIF read failed: #{e.message}"
    nil
  end
  
  def extract_from_original_metadata
    return nil unless @original_metadata&.dig('creation_year')
    
    year = @original_metadata['creation_year']
    creation_time = @original_metadata['creation_time']
    source = @original_metadata['source'] || 'unknown'
    
    Rails.logger.info "[ExifYearExtractor] Original metadata (#{source}): #{creation_time} (year: #{year})"
    
    # Solo usar la fecha si es razonablemente reciente
    current_year = Time.current.year
    
    if year >= (current_year - 2) && year <= current_year
      Rails.logger.info "[ExifYearExtractor] ✅ Using #{source} metadata year #{year} (within reasonable range)"
      year
    else
      Rails.logger.warn "[ExifYearExtractor] ❌ #{source} metadata year #{year} seems unrealistic, ignoring"
      nil
    end
  rescue => e
    Rails.logger.warn "[ExifYearExtractor] Original metadata read failed: #{e.message}"
    nil
  end

  def extract_from_file_metadata
    return nil unless File.exist?(@filepath)
    
    # Intentar usar birthtime (fecha de creación) primero, fallback a mtime
    file_time = begin
      File.birthtime(@filepath)  # Fecha de creación (cuando se tomó el screenshot)
    rescue NotImplementedError
      File.mtime(@filepath)      # Fallback para sistemas que no soportan birthtime
    end
    
    Rails.logger.info "[ExifYearExtractor] Processed file timestamp: #{file_time} (#{file_time.year})"
    
    # Solo usar la fecha del archivo si es razonablemente reciente
    # (asumimos que el usuario sube screenshots dentro de 2 años de tomarlos)
    current_year = Time.current.year
    file_year = file_time.year
    
    if file_year >= (current_year - 2) && file_year <= current_year
      Rails.logger.info "[ExifYearExtractor] Using processed file metadata year #{file_year} (within reasonable range)"
      file_year
    else
      Rails.logger.warn "[ExifYearExtractor] Processed file metadata year #{file_year} seems unrealistic, ignoring"
      nil
    end
  rescue => e
    Rails.logger.warn "[ExifYearExtractor] Processed file metadata read failed: #{e.message}"
    nil
  end
end