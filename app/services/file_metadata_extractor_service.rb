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
    Rails.logger.info "[FileMetadataExtractor] Tempfile path: #{tempfile_path}"
    
    # DIAGNÓSTICO: Ver si el uploaded_file tiene algún metadato adicional
    if @uploaded_file.respond_to?(:headers)
      Rails.logger.info "[FileMetadataExtractor] Upload headers: #{@uploaded_file.headers.inspect}"
    end

    # PRIORIDAD 1: EXIF para fotos reales (por si acaso, aunque esperamos 0%)
    creation_time = extract_creation_time_from_content(tempfile_path, @uploaded_file.content_type)
    
    if creation_time
      metadata[:creation_time] = creation_time.iso8601
      metadata[:creation_year] = creation_time.year
      metadata[:source] = 'exif'
      
      Rails.logger.info "[FileMetadataExtractor] ✅ EXIF date found: #{creation_time} (year: #{creation_time.year})"
    else
      # PRIORIDAD 2: Metadatos del archivo temporal (screenshots - 100% de casos esperados)
      # CRÍTICO: Intentar extraer la fecha REAL del archivo original, no cuando Rails lo procesó
      original_time = extract_original_file_time(tempfile_path)
      
      if original_time
        metadata[:creation_time] = original_time.iso8601
        metadata[:creation_year] = original_time.year
        metadata[:source] = 'filesystem'
        
        Rails.logger.info "[FileMetadataExtractor] ✅ Original file date: #{original_time} (year: #{original_time.year})"
      else
        Rails.logger.warn "[FileMetadataExtractor] ❌ No metadata found for #{@uploaded_file.original_filename}"
      end
    end

    metadata
  end

  private

  def extract_creation_time_from_content(filepath, content_type)
    case content_type.to_s.downcase
    when /jpeg|jpg/
      extract_jpeg_exif_date(filepath)
    when /png/
      extract_png_metadata_date(filepath)
    when /pdf/
      extract_pdf_metadata_date(filepath)
    else
      Rails.logger.info "[FileMetadataExtractor] No content metadata extractor for #{content_type}"
      nil
    end
  rescue => e
    Rails.logger.warn "[FileMetadataExtractor] Content metadata extraction failed: #{e.message}"
    nil
  end

  def extract_jpeg_exif_date(filepath)
    exif = EXIFR::JPEG.new(filepath)
    return nil unless exif.exif?
    
    # Prioridad: date_time_original (cuando se tomó) > date_time (cuando se modificó)
    date = exif.date_time_original || exif.date_time
    Rails.logger.info "[FileMetadataExtractor] Found JPEG EXIF date: #{date}" if date
    date
  rescue => e
    Rails.logger.warn "[FileMetadataExtractor] JPEG EXIF extraction failed: #{e.message}"
    nil
  end

  def extract_png_metadata_date(filepath)
    # PNG puede tener metadatos en chunks de texto, pero es menos común para screenshots
    # La mayoría de screenshots PNG no tienen fecha de creación embebida
    Rails.logger.info "[FileMetadataExtractor] PNG files typically don't have creation date metadata"
    nil
  end

  def extract_pdf_metadata_date(filepath)
    # PDFs pueden tener fecha de creación en metadatos del documento
    # Esto requeriría pdf-reader gem que ya tienes
    Rails.logger.info "[FileMetadataExtractor] PDF metadata extraction not implemented yet"
    nil
  end

  def extract_original_file_time(tempfile_path)
    # CRÍTICO: Para screenshots, necesitamos la fecha de creación ORIGINAL
    # El problema: el archivo temporal puede haber perdido la fecha original
    
    Rails.logger.info "[FileMetadataExtractor] Analyzing tempfile timestamps..."
    
    begin
      # Obtener todas las fechas disponibles del archivo temporal
      birthtime = begin
        File.birthtime(tempfile_path)
      rescue NotImplementedError
        nil
      end
      
      mtime = File.mtime(tempfile_path)
      ctime = File.ctime(tempfile_path)
      
      Rails.logger.info "[FileMetadataExtractor] Tempfile timestamps:"
      Rails.logger.info "  - birthtime: #{birthtime}" if birthtime
      Rails.logger.info "  - mtime: #{mtime}"
      Rails.logger.info "  - ctime: #{ctime}"
      
      # ESTRATEGIA: Si birthtime existe y es diferente de mtime, 
      # es más probable que preserve la fecha original del screenshot
      if birthtime && (birthtime != mtime) && birthtime < mtime
        Rails.logger.info "[FileMetadataExtractor] Using birthtime (likely original): #{birthtime}"
        return birthtime
      end
      
      # Si birthtime no existe o es igual a mtime, usar mtime
      # (aunque probablemente sea la fecha de upload, no del screenshot original)
      Rails.logger.info "[FileMetadataExtractor] Using mtime (may be upload time): #{mtime}"
      return mtime
      
    rescue => e
      Rails.logger.error "[FileMetadataExtractor] Failed to extract file timestamps: #{e.message}"
      nil
    end
  end
end