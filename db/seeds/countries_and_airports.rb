require 'csv'
require 'open-uri'

COUNTRIES_URL = 'https://davidmegginson.github.io/ourairports-data/countries.csv'
AIRPORTS_URL  = 'https://davidmegginson.github.io/ourairports-data/airports.csv'

# ── FASE 1: PAÍSES ──────────────────────────────────────
puts "\n== Cargando países del mundo =="

begin
  countries_csv = URI.open(COUNTRIES_URL).read
  rows = CSV.parse(countries_csv, headers: true)

  imported_countries = 0
  rows.each do |row|
    next if row['code'].blank? || row['name'].blank?
    next if row['code'].length != 2  # Solo ISO alpha-2
    
    # CRÍTICO: find_or_create_by NO toca registros existentes
    # Preserva los IDs ya asignados y sus FK en tickets
    country = Country.find_or_initialize_by(code: row['code'].upcase)
    
    # Solo actualizar nombre/continente si es nuevo registro
    if country.new_record?
      country.name      = row['name']
      country.continent = row['continent']
      # Valores fiscales por defecto (el admin los ajustará por país)
      country.max_days_allowed = 183
      country.save!
      imported_countries += 1
    end
  end

  puts "  Países nuevos importados: #{imported_countries}"
  puts "  Total países en BD: #{Country.count}"

rescue OpenURI::HTTPError => e
  puts "  ERROR: No se pudo descargar el archivo de países: #{e.message}"
  puts "  Verifica tu conexión a internet e intenta de nuevo."
  return
rescue => e
  puts "  ERROR inesperado cargando países: #{e.message}"
  return
end

# ── FASE 2: AEROPUERTOS ──────────────────────────────────
puts "\n== Cargando aeropuertos internacionales =="

# Filtros: solo large_airport y medium_airport CON código IATA
# Esto da ~3.500 aeropuertos internacionales relevantes
AIRPORT_TYPES = %w[large_airport medium_airport].freeze

begin
  airports_csv = URI.open(AIRPORTS_URL).read
  rows = CSV.parse(airports_csv, headers: true)

  # Precarga mapa de country code → country_id para evitar N+1
  country_map = Country.pluck(:code, :id).to_h

  imported = 0
  skipped_no_iata = 0
  skipped_no_country = 0
  errors = 0

  rows.each do |row|
    # Filtro 1: Solo tipos relevantes para viajes internacionales
    next unless AIRPORT_TYPES.include?(row['type'])
    
    # Filtro 2: Debe tener código IATA
    iata = row['iata_code'].to_s.strip.upcase
    if iata.blank? || iata.length != 3
      skipped_no_iata += 1
      next
    end
    
    # Filtro 3: El país debe existir en nuestra BD
    country_id = country_map[row['iso_country'].to_s.upcase]
    unless country_id
      skipped_no_country += 1
      next
    end
    
    begin
      # upsert por iata_code: actualiza si ya existe, crea si no
      Airport.find_or_initialize_by(iata_code: iata).tap do |airport|
        airport.name       = row['name'].to_s.truncate(255)
        airport.city       = row['municipality'].to_s.truncate(255)
        airport.country_id = country_id
        airport.save!
      end
      imported += 1
    rescue => e
      errors += 1
      puts "  ERROR en #{iata}: #{e.message}"
    end
  end

  puts "  Aeropuertos importados/actualizados: #{imported}"
  puts "  Saltados (sin IATA): #{skipped_no_iata}"
  puts "  Saltados (país no encontrado): #{skipped_no_country}"
  puts "  Errores: #{errors}"
  puts "  Total aeropuertos en BD: #{Airport.count}"

rescue OpenURI::HTTPError => e
  puts "  ERROR: No se pudo descargar el archivo de aeropuertos: #{e.message}"
  puts "  Verifica tu conexión a internet e intenta de nuevo."
  return
rescue => e
  puts "  ERROR inesperado cargando aeropuertos: #{e.message}"
  return
end
