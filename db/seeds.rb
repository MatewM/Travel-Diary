puts "Seeding countries and airports..."

# ──────────────────────────────────────────────────────────────
# FASE 1: Precarga de países de interés fiscal (opcional pero recomendada)
# ──────────────────────────────────────────────────────────────
# Estos países reciben configuración fiscal pre-cargada.
# Luego, countries_and_airports.rb descargará TODOS los países del mundo
# usando find_or_initialize_by, sin tocar los que ya existen.

countries_data = [
  { name: "Spain",          code: "ES", continent: "Europe", min_days_required: 183, max_days_allowed: 183 },
  { name: "France",         code: "FR", continent: "Europe", min_days_required: 183, max_days_allowed: 183 },
  { name: "Italy",          code: "IT", continent: "Europe", min_days_required: 183, max_days_allowed: 183 },
  { name: "Portugal",       code: "PT", continent: "Europe", min_days_required: 183, max_days_allowed: 183 },
  { name: "Germany",        code: "DE", continent: "Europe", min_days_required: 183, max_days_allowed: 183 },
  { name: "Netherlands",    code: "NL", continent: "Europe", min_days_required: nil,  max_days_allowed: 183 },
  { name: "Belgium",        code: "BE", continent: "Europe", min_days_required: 183, max_days_allowed: 183 },
  { name: "Switzerland",    code: "CH", continent: "Europe", min_days_required: 90,  max_days_allowed: 183 },
  { name: "United Kingdom", code: "GB", continent: "Europe", min_days_required: 183, max_days_allowed: 183 },
  { name: "Cyprus",         code: "CY", continent: "Europe", min_days_required: 60,  max_days_allowed: 183 }
]

countries_data.each do |attrs|
  Country.find_or_create_by!(code: attrs[:code]) do |country|
    country.assign_attributes(attrs.except(:code))
  end
end

puts "  ✓ #{countries_data.length} países base configurados"

# ──────────────────────────────────────────────────────────────
# FASE 2: Descarga de todos los países y aeropuertos desde OurAirports
# ──────────────────────────────────────────────────────────────
# Cargar db/seeds/countries_and_airports.rb que:
#   1. Descarga todos los países (~250 filas) y crea los que no existen
#   2. Descarga todos los aeropuertos grandes/medianos y asigna su país
load Rails.root.join('db/seeds/countries_and_airports.rb')
