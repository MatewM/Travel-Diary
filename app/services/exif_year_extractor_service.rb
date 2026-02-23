# frozen_string_literal: true

class ExifYearExtractorService
  def self.call(ticket)
    new(ticket).call
  end

  def initialize(ticket)
    @ticket = ticket
  end

  def call
    # IMPORTANTE: Los archivos son SCREENSHOTS de billetes
    # Necesitamos la fecha de cuando se creó el screenshot, NO cuando se subió a Rails
    full_date = extract_screenshot_creation_date
    if full_date
      Rails.logger.info "[ExifYearExtractor] ✅ Using screenshot creation date: #{full_date}"
      return { full_date: full_date, year: full_date.year.to_s }
    end

    # FALLBACK: Solo usar ticket.created_at si no hay metadata del screenshot
    ticket_creation_date = @ticket.created_at
    Rails.logger.info "[ExifYearExtractor] ❌ No screenshot metadata available, fallback to ticket creation date: #{ticket_creation_date}"
    
    { full_date: ticket_creation_date, year: ticket_creation_date.year.to_s }
  end

  private

  def extract_screenshot_creation_date
    # IMPORTANTE: Los archivos son SCREENSHOTS de billetes, NO fotos con EXIF
    # La fecha relevante es CUANDO SE HIZO EL SCREENSHOT (lastModified del archivo original)
    
    # PRIORIDAD ÚNICA: JavaScript lastModified (fecha cuando se creó el screenshot)
    original_metadata = @ticket.original_file_metadata
    if original_metadata.present?
      timestamp = original_metadata['lastModified']
      if timestamp
        full_date = Time.at(timestamp / 1000.0).utc
        year = full_date.year
        current_year = Time.current.year

        # Solo usar si está en rango razonable (±2 años)
        if year >= (current_year - 2) && year <= current_year
          Rails.logger.info "[ExifYearExtractor] ✅ Using screenshot creation date (lastModified): #{full_date}"
          return full_date
        else
          Rails.logger.warn "[ExifYearExtractor] ⚠️ Screenshot date #{full_date} outside reasonable range (#{current_year-2}-#{current_year})"
        end
      else
        Rails.logger.warn "[ExifYearExtractor] ⚠️ No lastModified timestamp in metadata"
      end
    else
      Rails.logger.warn "[ExifYearExtractor] ⚠️ No original_file_metadata available"
    end

    # NO intentar EXIF (screenshots no tienen date_time_original)
    # NO usar file system timestamps (siempre son fecha de upload a Rails)
    Rails.logger.warn "[ExifYearExtractor] ❌ No screenshot creation date available in metadata"
    nil
  end

end