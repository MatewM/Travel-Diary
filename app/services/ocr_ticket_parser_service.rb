# frozen_string_literal: true

class OcrTicketParserService
  def self.call(text, target_year: nil, full_date: nil)
    new(text, target_year: target_year, full_date: full_date).call
  end

  def initialize(text, target_year: nil, full_date: nil)
    @text = text || ""
    @target_year = target_year
    @full_date = full_date
  end

  def call
    return nil if @text.blank?

    data = {
      flight_number: extract_flight_number,
      airline: extract_airline,
      departure_airport: nil,
      arrival_airport: nil,
      flight_date: nil,
      confidence: {}
    }

    # Extraer aeropuertos y validarlos con contexto
    airports = extract_airports_with_context
    data[:departure_airport] = airports[:departure]
    data[:arrival_airport] = airports[:arrival]
    data[:confidence][:departure_airport] = airports[:departure_conf]
    data[:confidence][:arrival_airport] = airports[:arrival_conf]

    # Extraer fecha
    date_info = extract_date
    data[:flight_date] = date_info[:date]
    data[:confidence][:flight_date] = date_info[:conf]
    data[:year_source] = date_info[:year_source]
    data[:year_requires_verification] = date_info[:year_requires_verification]

    data.with_indifferent_access
  end

  private

  def extract_flight_number
    # Patrones comunes de número de vuelo: AA1234, IB 3202, FR 123
    match = @text.match(/\b([A-Z]{2,3})\s?(\d{1,4}[A-Z]?)\b/)
    match ? "#{match[1]}#{match[2]}".gsub(/\s+/, "") : nil
  end

  def extract_airline
    nil
  end

  def extract_airports_with_context
    # Buscamos códigos IATA con palabras clave de contexto
    # FROM: BCN, TO: MAD, ORIGIN: LHR, DESTINATION: JFK
    # También en español: ORIGEN, DESTINO, DE, A
    
    context_patterns = {
      departure: [/\b(?:FROM|ORIGIN|ORIGEN|DE|DEP|DEPARTURE)\b[:\s]*([A-Z]{3})\b/i],
      arrival: [/\b(?:TO|DESTINATION|DESTINO|A|ARR|ARRIVAL)\b[:\s]*([A-Z]{3})\b/i]
    }

    results = { departure: nil, arrival: nil, departure_conf: "low", arrival_conf: "low" }

    context_patterns[:departure].each do |pattern|
      match = @text.match(pattern)
      if match && Airport.exists?(iata_code: match[1].upcase)
        results[:departure] = match[1].upcase
        results[:departure_conf] = "high"
        break
      end
    end

    context_patterns[:arrival].each do |pattern|
      match = @text.match(pattern)
      if match && Airport.exists?(iata_code: match[1].upcase)
        results[:arrival] = match[1].upcase
        results[:arrival_conf] = "high"
        break
      end
    end

    # Si no encontramos con contexto, buscamos cualquier código IATA válido
    if results[:departure].nil? || results[:arrival].nil?
      found_codes = @text.scan(/\b[A-Z]{3}\b/).uniq
      valid_codes = found_codes.select { |code| Airport.exists?(iata_code: code) }
      
      results[:departure] ||= valid_codes[0]
      results[:arrival] ||= valid_codes[1]
      results[:departure_conf] = "medium" if results[:departure] && results[:departure_conf] == "low"
      results[:arrival_conf] = "medium" if results[:arrival] && results[:arrival_conf] == "low"
    end

    results
  end

  def extract_date
    # Buscamos formatos DD/MM/YYYY, DD-MM-YYYY, DD MMM YYYY, DD MMM
    # Meses en varios idiomas
    months = %w[JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC ENE FEB MAR ABR MAY JUN JUL AGO SEP OCT NOV DIC]
    months_regex = months.uniq.join("|")

    # 1. Fecha completa con año
    full_date_match = @text.match(/\b(\d{1,2})[\/\-\s](#{months_regex}|\d{1,2})[\/\-\s](\d{2,4})\b/i)
    if full_date_match
      day = full_date_match[1]
      month = full_date_match[2]
      year = full_date_match[3]
      year = "20#{year}" if year.length == 2
      
      begin
        parsed_date = Date.parse("#{day} #{month} #{year}")
        return {
          date: parsed_date.iso8601,
          conf: "high",
          year_source: "explicit",
          year_requires_verification: false
        }
      rescue ArgumentError
      end
    end

    # 2. Día y Mes solamente
    day_month_match = @text.match(/\b(\d{1,2})[\/\-\s](#{months_regex})\b/i)
    if day_month_match && @target_year
      day = day_month_match[1]
      month = day_month_match[2]
      
      begin
        estimated_date = Date.parse("#{day} #{month} #{@target_year}")
        conf = "low"
        year_source = "estimated"
        requires_ver = true

        if @full_date && (estimated_date - @full_date.to_date).abs <= 30
          conf = "medium"
          year_source = "metadata_match"
          requires_ver = false
        end

        return {
          date: estimated_date.iso8601,
          conf: conf,
          year_source: year_source,
          year_requires_verification: requires_ver
        }
      rescue ArgumentError
      end
    end

    { date: nil, conf: "low", year_source: "unknown", year_requires_verification: true }
  end
end
