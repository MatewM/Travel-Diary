require_relative "config/environment"
require "mini_magick"
require "zxing"

if ARGV.empty?
  puts "Uso: bundle exec ruby test_qr_variants.rb <ruta_al_archivo>"
  exit 1
end

filepath = ARGV[0]

unless File.exist?(filepath)
  puts "Error: El archivo #{filepath} no existe."
  exit 1
end

puts "=== TEST QR VARIANTS ==="
puts "Archivo: #{filepath}"
puts

resize_variants = [
  { scale: "200%", method: nil,        label: "resize_200" },
  { scale: "400%", method: nil,        label: "resize_400" },
  { scale: "600%", method: nil,        label: "resize_600" },
  { scale: "800%", method: nil,        label: "resize_800" },
  { scale: "400%", method: "Lanczos",  label: "resize_400_lanczos" },
  { scale: "600%", method: "Mitchell", label: "resize_600_mitchell" }
]

border_crops = [
  { pct: 0.05, label: "crop_5" },
  { pct: 0.10, label: "crop_10" },
  { pct: 0.20, label: "crop_20" },
  { pct: 0.30, label: "crop_30" }
]

center_crops = [
  { keep: 0.80, label: "center_keep_80" },
  { keep: 0.60, label: "center_keep_60" },
  { keep: 0.40, label: "center_keep_40" }
]

preprocessing_variants = %i[none light current]

def apply_preprocessing(img, variant)
  case variant
  when :none
    # nada
  when :light
    img.colorspace "Gray"
    img.normalize
    img.unsharp "0x1"
  when :moderate
    img.colorspace "Gray"
    img.contrast
    img.normalize
    img.unsharp "0x2"
  when :current
    img.strip
    img.alpha "off"
    img.background "white"
    img.flatten
    img.colorspace "Gray"
    img.depth "8"
    img.unsharp "0x0.75"
  end
end

def test_variant(original_path, resize_cfg:, preproc:, border_crop: nil, center_crop: nil)
  desc_parts = []
  desc_parts << resize_cfg[:label]
  desc_parts << "pre_#{preproc}"
  desc_parts << "border_#{border_crop[:label]}_#{border_crop[:side]}" if border_crop
  desc_parts << "center_#{center_crop[:label]}" if center_crop

  tmp = Tempfile.new([ "qr_variant", ".png" ])
  tmp.close

  success = false
  decoded_by = nil
  content = nil

  begin
    img = MiniMagick::Image.open(original_path)
    img.auto_orient

    if resize_cfg[:method]
      img.filter resize_cfg[:method]
    end
    img.resize resize_cfg[:scale] if resize_cfg[:scale]

    # Crops de borde (eliminar franjas)
    if border_crop
      w = img.width
      h = img.height
      pct = border_crop[:pct]
      dx = (w * pct).round
      dy = (h * pct).round

      cw = w
      ch = h
      cx = 0
      cy = 0

      case border_crop[:side]
      when :top
        cw = w
        ch = h - dy
        cx = 0
        cy = dy
      when :bottom
        cw = w
        ch = h - dy
        cx = 0
        cy = 0
      when :left
        cw = w - dx
        ch = h
        cx = dx
        cy = 0
      when :right
        cw = w - dx
        ch = h
        cx = 0
        cy = 0
      end

      img.crop "#{cw}x#{ch}+#{cx}+#{cy}"
    end

    # Crops centrados
    if center_crop
      w = img.width
      h = img.height
      keep = center_crop[:keep]
      cw = (w * keep).round
      ch = (h * keep).round
      cx = ((w - cw) / 2.0).round
      cy = ((h - ch) / 2.0).round
      img.crop "#{cw}x#{ch}+#{cx}+#{cy}"
    end

    apply_preprocessing(img, preproc)

    img.write(tmp.path)

    # Probar ZXing
    begin
      result = ZXing.decode(tmp.path.to_s)
      if result.present?
        success = true
        decoded_by = "ZXing"
        content = result
      end
    rescue => e
      puts "ZXing error en variante #{desc_parts.join(' | ')}: #{e.message}"
    end

    # Probar ZBar si ZXing no encontró nada
    unless success
      out = `zbarimg --raw -q "#{tmp.path}" 2>/dev/null`.strip
      if out.present?
        success = true
        decoded_by = "ZBar"
        content = out
      end
    end
  ensure
    File.delete(tmp.path) if File.exist?(tmp.path)
  end

  {
    success: success,
    decoded_by: decoded_by,
    content: content,
    description: desc_parts.join(" | ")
  }
end

results = []

resize_variants.each do |resize_cfg|
  preprocessing_variants.each do |preproc|
    # 1. Solo resize + preproc
    results << test_variant(filepath, resize_cfg: resize_cfg, preproc: preproc)

    # 2. Con crops de borde (top/bottom/left/right)
    border_crops.each do |crop|
      %i[top bottom left right].each do |side|
        cfg = crop.merge(side: side)
        results << test_variant(filepath, resize_cfg: resize_cfg, preproc: preproc, border_crop: cfg)
      end
    end

    # 3. Con crops centrados
    center_crops.each do |crop|
      results << test_variant(filepath, resize_cfg: resize_cfg, preproc: preproc, center_crop: crop)
    end
  end
end

successful = results.select { |r| r[:success] }

puts
puts "=== RESULTADOS ==="
puts "Total variantes probadas: #{results.size}"
puts "Exitosas: #{successful.size}"
puts

if successful.any?
  puts "Variantes exitosas:"
  successful.each do |r|
    snippet = r[:content].to_s.gsub(/\s+/, " ")[0..80]
    puts "  ✅ #{r[:description]} (#{r[:decoded_by]}) => #{snippet.inspect}"
  end
else
  puts "No hubo variantes exitosas."
end

