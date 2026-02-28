namespace :db do
  namespace :validate do
    desc 'Valida la integridad de referencias entre airports y countries'
    task airport_countries_integrity: :environment do
      puts "\n== Validando integridad: airports → countries =="

      # Verificar que no haya airports sin país
      orphaned = Airport.where(country_id: nil).count
      if orphaned.zero?
        puts "  ✓ Todos los aeropuertos tienen un país asignado"
      else
        puts "  ✗ #{orphaned} aeropuertos SIN país asignado"
        Airport.where(country_id: nil).limit(10).each do |ap|
          puts "    - #{ap.iata_code}: #{ap.name}"
        end
      end

      # Verificar que todos los country_id existan en countries
      invalid_fks = Airport.where.not(
        country_id: Country.pluck(:id)
      ).count

      if invalid_fks.zero?
        puts "  ✓ Todas las FK country_id apuntan a países válidos"
      else
        puts "  ✗ #{invalid_fks} aeropuertos con FK inválida"
      end

      # Estadísticas generales
      total_airports = Airport.count
      total_countries = Country.count
      countries_with_airports = Airport.distinct.count(:country_id)

      puts "\nEstadísticas:"
      puts "  • Países en BD: #{total_countries}"
      puts "  • Países con aeropuertos: #{countries_with_airports}"
      puts "  • Aeropuertos en BD: #{total_airports}"
      puts "  • Promedio de aeropuertos por país: #{(total_airports.to_f / countries_with_airports).round(2)}"

      # Mostrar países SIN aeropuertos (pueden ser válidos si no hay aeropuertos internacionales)
      countries_without_airports = Country.where.not(
        id: Airport.select(:country_id).distinct
      ).count

      puts "  • Países sin aeropuertos: #{countries_without_airports}"

      puts "\n== Validación completada ✓\n"
    end

    desc 'Valida que existan SVG de banderas para todos los países'
    task flag_assets: :environment do
      puts "\n== Validando assets de banderas =="

      flags_dir = Rails.root.join('app/assets/images/flags')
      existing_flags = Dir.glob(flags_dir.join('*.svg')).map { |f| File.basename(f, '.svg') }.to_set

      missing = 0
      Country.all.each do |country|
        flag_code = country.code.downcase
        unless existing_flags.include?(flag_code)
          puts "  ✗ Falta bandera para: #{country.code} (#{country.name})"
          missing += 1
        end
      end

      if missing.zero?
        puts "  ✓ Todas las banderas disponibles"
      else
        puts "  ✗ #{missing} banderas faltantes"
      end

      puts "  • Banderas en assets: #{existing_flags.size}"
      puts "  • Países en BD: #{Country.count}"
      puts "\n== Validación completada ✓\n"
    end
  end
end
