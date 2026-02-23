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
    # PRIORIDAD 1: Metadatos originales capturados por JS (los que guardamos en original_file_metadata)
    full_date = extract_full_date_from_original_metadata
    if full_date
      Rails.logger.info "[ExifYearExtractor] ✅ Usando fecha completa de JavaScript: #{full_date}"
      return { full_date: full_date, year: full_date.year.to_s }
    end

    # PRIORIDAD 2: EXIF real del archivo (solo si lo anterior falla)
    full_date = extract_full_date_from_exif if jpeg?
    if full_date
      Rails.logger.info "[ExifYearExtractor] Found EXIF full date: #{full_date}"
      return { full_date: full_date, year: full_date.year.to_s }
    end

    # Fallback: usar metadatos del archivo procesado
    full_date = extract_full_date_from_file_metadata
    if full_date
      Rails.logger.info "[ExifYearExtractor] Found processed file metadata full date: #{full_date}"
      return { full_date: full_date, year: full_date.year.to_s }
    end

    Rails.logger.info "[ExifYearExtractor] No metadata found"
    nil
  end

  private

  def jpeg?
    @mimetype.to_s.include?('jpeg') || @mimetype.to_s.include?('jpg')
  end

  def extract_full_date_from_exif
    exif = EXIFR::JPEG.new(@filepath)
    return nil unless exif.exif?
    # Usamos date_time_original (cuando se tomó la foto), NO date_time (cuando se modificó)
    date = exif.date_time_original || exif.date_time
    date
  rescue => e
    Rails.logger.warn "[ExifYearExtractor] EXIF read failed: #{e.message}"
    nil
  end
  
  def extract_full_date_from_original_metadata
    return nil if @original_metadata.blank?

    # El JS envía 'lastModified', intentamos sacarlo de ahí
    timestamp = @original_metadata['lastModified']
    if timestamp
      # Convertir de milisegundos (JS) a segundos (Ruby)
      full_date = Time.at(timestamp / 1000.0).utc
      year = full_date.year
      source = @original_metadata['source'] || 'javascript'

      Rails.logger.info "[ExifYearExtractor] Original metadata (#{source}): timestamp #{timestamp} -> full_date #{full_date}"

      # Solo usar la fecha si es razonablemente reciente
      current_year = Time.current.year

      if year >= (current_year - 2) && year <= current_year
        Rails.logger.info "[ExifYearExtractor] ✅ Using #{source} metadata full date #{full_date} (within reasonable range)"
        full_date
      else
        Rails.logger.warn "[ExifYearExtractor] ❌ #{source} metadata full date #{full_date} seems unrealistic, ignoring"
        nil
      end
    else
      Rails.logger.warn "[ExifYearExtractor] No lastModified timestamp in original metadata"
      nil
    end
  rescue => e
    Rails.logger.warn "[ExifYearExtractor] Original metadata read failed: #{e.message}"
    nil
  end

  def extract_full_date_from_file_metadata
    return nil unless File.exist?(@filepath)
    
    # Intentar usar birthtime (fecha de creación) primero, fallback a mtime
    file_time = begin
      File.birthtime(@filepath)  # Fecha de creación (cuando se tomó el screenshot)
    rescue NotImplementedError
      File.mtime(@filepath)      # Fallback para sistemas que no soportan birthtime
    end
    
    Rails.logger.info "[ExifYearExtractor] Processed file timestamp: #{file_time}"
    
    # Solo usar la fecha del archivo si es razonablemente reciente
    # (asumimos que el usuario sube screenshots dentro de 2 años de tomarlos)
    current_year = Time.current.year
    file_year = file_time.year
    
    if file_year >= (current_year - 2) && file_year <= current_year
      Rails.logger.info "[ExifYearExtractor] Using processed file metadata full date #{file_time} (within reasonable range)"
      file_time
    else
      Rails.logger.warn "[ExifYearExtractor] Processed file metadata full date #{file_time} seems unrealistic, ignoring"
      nil
    end
  rescue => e
    Rails.logger.warn "[ExifYearExtractor] Processed file metadata read failed: #{e.message}"
    nil
  end
end