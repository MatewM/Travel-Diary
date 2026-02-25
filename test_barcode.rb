require_relative "config/environment"
require "mini_magick"

if ARGV.empty?
  puts "Uso: bundle exec ruby test_barcode.rb <ruta_al_archivo>"
  exit 1
end

filepath = ARGV[0]

unless File.exist?(filepath)
  puts "Error: El archivo #{filepath} no existe."
  exit 1
end

puts "=== Probando ZXing (Original) ==="
begin
  require 'zxing'
  result = ZXing.decode(filepath.to_s)
  if result.present?
    puts "✅ ZXing éxito! Contenido:\n#{result}"
  else
    puts "❌ ZXing no encontró nada (nil/vacío)."
  end
rescue => e
  puts "❌ ZXing falló con excepción: #{e.class} - #{e.message}"
end

puts "\n=== Probando ZBar (Original) ==="
begin
  out = `zbarimg --raw -q "#{filepath}" 2>/dev/null`.strip
  data = out.presence

  if data.present?
    puts "✅ ZBar éxito! Contenido:\n#{data}"
  else
    puts "❌ ZBar no encontró nada (nil/vacío)."
  end
rescue => e
  puts "❌ ZBar falló con excepción: #{e.class} - #{e.message}"
end

puts "\n=== Creando versión preprocesada (MiniMagick) ==="
begin
  processed = Tempfile.new(["barcode_processed", ".png"])
  processed.close

  img = MiniMagick::Image.open(filepath)
  img.resize "400%"        # Ampliación extrema para QR pequeños
  img.colorspace "Gray"    # Conversión a escala de grises
  img.contrast             # Aumento de contraste
  img.normalize            # Normalización
  img.threshold "40%"      # Conversión blanco/negro más agresiva
  img.sharpen "0x3"        # Sharpening más fuerte
  img.format "png"         # Mejor formato para procesamiento
  img.write(processed.path)
  puts "✅ Imagen procesada guardada en #{processed.path}"
  
  puts "\n=== Probando ZXing (Procesada) ==="
  begin
    result = ZXing.decode(processed.path)
    if result.present?
      puts "✅ ZXing (Procesada) éxito! Contenido:\n#{result}"
    else
      puts "❌ ZXing (Procesada) no encontró nada."
    end
  rescue => e
    puts "❌ ZXing (Procesada) falló: #{e.message}"
  end

  puts "\n=== Probando ZBar (Procesada) ==="
  begin
    out = `zbarimg --raw -q "#{processed.path}" 2>/dev/null`.strip
    data = out.presence

    if data.present?
      puts "✅ ZBar (Procesada) éxito! Contenido:\n#{data}"
    else
      puts "❌ ZBar (Procesada) no encontró nada."
    end
  rescue => e
    puts "❌ ZBar (Procesada) falló: #{e.message}"
  end
  
rescue => e
  puts "❌ Falló el preprocesamiento: #{e.message}"
ensure
  File.delete(processed.path) if processed && File.exist?(processed.path)
end
