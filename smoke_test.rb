#!/usr/bin/env ruby
# frozen_string_literal: true

# Smoke test script for ParseTicketService with specific image
require_relative 'config/environment'

puts "=== SMOKE TEST: ParseTicketService con Captura de pantalla 2026-02-25 194355.jpg ==="
puts "Timestamp: #{Time.current}"
puts

# Path del archivo de prueba
test_image_path = Rails.root.join('public/Pruebas_qr_smoke_test/Captura de pantalla 2026-02-25 194355.jpg')

unless File.exist?(test_image_path)
  puts "❌ ERROR: Archivo de prueba no encontrado: #{test_image_path}"
  exit 1
end

puts "📁 Archivo encontrado: #{test_image_path}"
puts "📏 Tamaño: #{File.size(test_image_path)} bytes"
puts

# Verificar que sea una imagen
mimetype = `file --mime-type "#{test_image_path}"`.strip.split(': ').last rescue 'unknown'
puts "📋 Tipo MIME detectado: #{mimetype}"

if mimetype.start_with?('image/')
  puts "✅ Es una imagen válida"
else
  puts "⚠️  No es una imagen reconocida"
end
puts

# Test 1: BarcodeExtractorService directo
puts "🔍 TEST 1: BarcodeExtractorService.call(filepath, '2026-02-25')"
puts "⏳ Ejecutando..."

start_time = Time.now
result = BarcodeExtractorService.call(test_image_path.to_s, '2026-02-25')
end_time = Time.now

duration = (end_time - start_time).round(2)

puts "⏱️  Duración: #{duration} segundos"

if result.present?
  puts "✅ ÉXITO: Barcode encontrado!"
  puts "📊 Resultados:"
  result.each do |key, value|
    puts "   #{key}: #{value.inspect}"
  end
else
  puts "❌ FALLÓ: No se pudo extraer barcode"
end
puts

# Test 2: Simular el flujo completo de ParseTicketService
puts "🔍 TEST 2: Simulación del flujo completo de ParseTicketService"
puts "⏳ Ejecutando..."

# Simular la lógica de convert_pdf_to_cropped_image (aunque sea imagen, probamos el path directo)
filepath = test_image_path.to_s

# Simular extracción de fecha (usando la fecha del nombre del archivo)
extraction_result = {
  full_date: Date.parse('2026-02-25'),
  year: 2026
}

full_date = extraction_result[:full_date]
target_year = extraction_result[:year]

puts "📅 Fecha extraída: #{full_date} (año #{target_year})"

# Llamar a BarcodeExtractorService
puts "🔍 Llamando BarcodeExtractorService..."
bcbp_result = BarcodeExtractorService.call(filepath, full_date.strftime("%Y-%m-%d"))

if bcbp_result.present? && bcbp_result.with_indifferent_access[:source].to_s == "bcbp"
  puts "✅ BCBP parsing exitoso!"

  parsed_data = bcbp_result.with_indifferent_access

  # Buscar países por IATA
  dep_country = Airport.find_by(iata_code: parsed_data[:departure_airport])&.country rescue nil
  arr_country = Airport.find_by(iata_code: parsed_data[:arrival_airport])&.country rescue nil

  puts "📊 Datos extraídos:"
  puts "   ✈️  Vuelo: #{parsed_data[:airline]} #{parsed_data[:flight_number]}"
  puts "   🛫 Origen: #{parsed_data[:departure_airport]} (#{dep_country&.name || 'País no encontrado'})"
  puts "   🛬 Destino: #{parsed_data[:arrival_airport]} (#{arr_country&.name || 'País no encontrado'})"
  puts "   📅 Fecha: #{parsed_data[:flight_date]}"
  puts "   ✅ Estado: #{parsed_data[:date_status]}"

  ticket_status = parsed_data[:date_status] == :autoverified ? :auto_verified : :needs_review
  puts "   🎫 Status del ticket: #{ticket_status}"

else
  puts "❌ BCBP parsing falló"
  if bcbp_result.present?
    puts "   Datos disponibles: #{bcbp_result.keys.inspect}"
  else
    puts "   Sin resultados"
  end
end

puts
puts "=== FIN DEL SMOKE TEST ==="