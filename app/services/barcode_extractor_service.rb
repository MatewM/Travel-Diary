# frozen_string_literal: true

require "zxing"
require "uri"
require "cgi"
class BarcodeExtractorService
  def self.call(filepath, capturedate)
    Rails.logger.info "BarcodeExtractorService: Starting for #{filepath}"
    return nil if filepath.nil? || !File.exist?(filepath)

    Timeout.timeout(30) do
      raw_string = attempt_decode(filepath)

      if raw_string.present?
        parse_and_return(raw_string, capturedate)
      else
        Rails.logger.warn "BarcodeExtractorService: No QR/barcode found after attempts"
        nil
      end
    end
  rescue Timeout::Error
    Rails.logger.error "BarcodeExtractorService: TIMEOUT after 30 seconds"
    nil
  rescue => e
    Rails.logger.error "BarcodeExtractorService: FAILED #{e.message}"
    nil
  end

  private_class_method def self.attempt_decode(filepath)
    Rails.logger.info "BarcodeExtractorService: Starting attempt_decode for #{filepath}"

    # Log de dimensiones de la imagen original para debugging de screenshots.
    begin
      require "mini_magick"
      dim_img = MiniMagick::Image.open(filepath)
      Rails.logger.info "BarcodeExtractorService: Original image dimensions #{dim_img.width}x#{dim_img.height}"
    rescue => e
      Rails.logger.warn "BarcodeExtractorService: Could not read original image dimensions: #{e.message}"
    end

    # Intento 1: ZXing directo sobre la imagen original.
    # ZXing.decode retorna un String directamente (o nil si no decodifica).
    Rails.logger.info "BarcodeExtractorService: [1] Trying ZXing on original image..."
    begin
      result = ZXing.decode(filepath.to_s)
      if result.present?
        Rails.logger.info "BarcodeExtractorService: [1] ZXingCPP SUCCESS. Raw #{result.gsub(/\s/, ' ')[0..79]}"
        return result
      else
        Rails.logger.info "BarcodeExtractorService: [1] ZXing found nothing on original"
      end
    rescue => e
      Rails.logger.warn "BarcodeExtractorService: [1] ZXing error on original: #{e.message}"
    end

    # Intento 2: ZBar CLI sobre imagen original
    Rails.logger.info "BarcodeExtractorService: [2] Trying ZBar on original image..."
    result = zbar_decode(filepath)
    if result.present?
      Rails.logger.info "BarcodeExtractorService: [2] ZBar SUCCESS on original: #{result[0..100]}..."
      return result
    else
      Rails.logger.info "BarcodeExtractorService: [2] ZBar found nothing on original"
    end

    # Intento 2.5: crops sobre imagen original
    Rails.logger.info "BarcodeExtractorService: [2.5] Trying crop variants on original image..."
    crop_variants(filepath) do |crop_path, label|
      result = try_decode_both(crop_path, label: "[2.5] #{label}")
      return result if result.present?
    end

    # Intentos 3 y 4: Con múltiples variantes de preprocesamiento de imagen
    Rails.logger.info "BarcodeExtractorService: [3-4] Trying with image preprocessing variants..."
    processed_paths = []
    begin
      processed_paths = preprocess_variants(filepath)
      if processed_paths.any?
        processed_paths.each_with_index do |processed_path, idx|
          Rails.logger.info "BarcodeExtractorService: [3] Trying ZXing on processed variant ##{idx + 1}..."
          begin
            result = Timeout.timeout(5) { ZXing.decode(processed_path) }
            if result.present?
              Rails.logger.info "BarcodeExtractorService: [3] ZXing SUCCESS on processed variant ##{idx + 1}: #{result[0..100]}..."
              return result
            else
              Rails.logger.info "BarcodeExtractorService: [3] ZXing found nothing on processed variant ##{idx + 1}"
            end
          rescue => e
            Rails.logger.warn "BarcodeExtractorService: [3] ZXing error on processed variant ##{idx + 1}: #{e.message}"
          end

          Rails.logger.info "BarcodeExtractorService: [4] Trying ZBar on processed variant ##{idx + 1}..."
          result = zbar_decode(processed_path)
          if result.present?
            Rails.logger.info "BarcodeExtractorService: [4] ZBar SUCCESS on processed variant ##{idx + 1}: #{result[0..100]}..."
            return result
          else
            Rails.logger.info "BarcodeExtractorService: [4] ZBar found nothing on processed variant ##{idx + 1}"
          end

          # Intento 4.5: crops sobre cada imagen preprocesada
          Rails.logger.info "BarcodeExtractorService: [4.5] Trying crop variants on processed variant ##{idx + 1}..."
          crop_variants(processed_path) do |crop_path, label|
            result = try_decode_both(crop_path, label: "[4.5 v#{idx + 1}] #{label}")
            return result if result.present?
          end
        end
      else
        Rails.logger.warn "BarcodeExtractorService: Preprocessing variants failed or produced no images, skipping attempts 3-4"
      end
    ensure
      processed_paths.each do |processed_path|
        File.delete(processed_path) if processed_path && File.exist?(processed_path)
      end
    end

    Rails.logger.info "BarcodeExtractorService: All attempts failed"
    nil
  end

  private_class_method def self.zbar_decode(filepath)
    Timeout.timeout(10) do
      out = `zbarimg --raw -q "#{filepath}" 2>/dev/null`.strip
      out.presence
    end
  rescue Timeout::Error
    Rails.logger.warn "BarcodeExtractorService: ZBar CLI timeout after 10 seconds"
    nil
  rescue => e
    Rails.logger.warn "BarcodeExtractorService ZBar CLI failed: #{e.message}"
    nil
  end

  private_class_method def self.preprocess_variants(filepath)
    require "mini_magick"
    processed_paths = []

    Timeout.timeout(40) do
      base = MiniMagick::Image.open(filepath)
      w = base.width
      h = base.height
      Rails.logger.info "BarcodeExtractorService: preprocess_variants base image #{w}x#{h}"

      variants = [
        { scale: "200%", filter: nil, label: "200" },
        { scale: "400%", filter: nil, label: "400" }
      ]

      variants.each do |cfg|
        tmp = Tempfile.new([ "barcode_processed_#{cfg[:label]}", ".png" ])
        tmp.close

        img = base.clone
        img.combine_options do |c|
          c.auto_orient
          c.filter cfg[:filter] if cfg[:filter]
          c.resize cfg[:scale] if cfg[:scale]
          c.strip
          c.alpha "off"
          c.background "white"
          c.flatten
          c.colorspace "Gray"
          c.depth "8"
          c.unsharp "0x0.75"
        end

        img.write(tmp.path)
        Rails.logger.info "BarcodeExtractorService: Preprocessed variant #{cfg[:label]} at #{tmp.path}"
        processed_paths << tmp.path
      end
    end

    processed_paths
  rescue Timeout::Error
    Rails.logger.warn "BarcodeExtractorService: MiniMagick preprocess_variants timeout after 40 seconds"
    processed_paths.each { |path| File.delete(path) if File.exist?(path) }
    []
  rescue => e
    Rails.logger.warn "BarcodeExtractorService: MiniMagick preprocess_variants failed: #{e.message}"
    processed_paths.each { |path| File.delete(path) if File.exist?(path) }
    []
  end

  # Genera recortes del fichero eliminando franjas (top/bottom/left/right)
  # para cada porcentaje en `percents`. Cede un tempfile al bloque y garantiza
  # su eliminación en el ensure.
  private_class_method def self.crop_variants(filepath, percents: [ 0.12, 0.24, 0.4 ])
    require "mini_magick"
    temps = []

    begin
      img = MiniMagick::Image.open(filepath)
      w = img.width
      h = img.height
      Rails.logger.info "BarcodeExtractorService: crop_variants base image #{w}x#{h}, percents=#{percents.inspect}"

      percents.each do |pct|
        dx = (w * pct).round
        dy = (h * pct).round

        {
          "crop_top_#{pct}"    => [ w,        h - dy,    0,     dy ],
          "crop_bottom_#{pct}" => [ w,        h - dy,    0,     0  ],
          "crop_left_#{pct}"   => [ w - dx,   h,         dx,    0  ],
          "crop_right_#{pct}"  => [ w - dx,   h,         0,     0  ]
        }.each do |label, (cw, ch, cx, cy)|
          tmp = Tempfile.new([ "barcode_crop_#{label}", ".png" ])
          tmp.close
          temps << tmp

          cropped = MiniMagick::Image.open(filepath)
          cropped.crop "#{cw}x#{ch}+#{cx}+#{cy}"
          cropped.write(tmp.path)

          yield tmp.path, label
        end
      end
    rescue => e
      Rails.logger.warn "BarcodeExtractorService: crop_variants error: #{e.message}"
    ensure
      temps.each { |t| File.delete(t.path) if t && File.exist?(t.path) }
    end
  end

  # Intenta decodificar filepath con ZXing (timeout 2s) y luego con zbar.
  # Retorna el primer resultado válido o nil.
  private_class_method def self.try_decode_both(filepath, label:)
    begin
      result = Timeout.timeout(2) { ZXing.decode(filepath) }
      if result.present?
        Rails.logger.info "BarcodeExtractorService: #{label} ZXing SUCCESS: #{result.gsub(/\s/, ' ')[0..79]}"
        return result
      end
    rescue => e
      Rails.logger.warn "BarcodeExtractorService: #{label} ZXing error: #{e.message}"
    end

    result = zbar_decode(filepath)
    if result.present?
      Rails.logger.info "BarcodeExtractorService: #{label} ZBar SUCCESS: #{result[0..79]}"
      return result
    end

    nil
  end

  private_class_method def self.parse_and_return(raw_string, capturedate)
    Rails.logger.info "BarcodeExtractorService: Decoded #{raw_string[0..60]}..."
    result = BcbpParserService.process_decoded_string(raw_string, capturedate)
    unless result
      Rails.logger.info "BarcodeExtractorService: decoded but parse failed. Raw: #{raw_string.to_s.gsub("\n", "\\n")[0..79]}"
      return nil
    end

    {
      source:            :bcbp_barcode,
      flight_number:     result[:flight_number],
      airline:           result[:airline],
      departure_airport: result[:departure_airport],
      arrival_airport:   result[:arrival_airport],
      flight_date:       result[:flight_date]&.iso8601,
      date_status:       result[:date_status],
      julian_day:        result[:julian_day],
      year_digit:        result[:year_digit]
    }
  rescue => e
    Rails.logger.warn "BarcodeExtractorService: BCBP parse failed: #{e.message}"
    Rails.logger.info "BarcodeExtractorService: decoded but parse failed. Raw: #{raw_string.to_s.gsub("\n", "\\n")[0..79]}"
    nil
  end
end
