# frozen_string_literal: true

class PdfTicketParserService
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

    # Extraer aeropuertos y validarlos
    airports = extract_airports
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
    # Muy difícil de extraer por regex pura, pero podemos buscar nombres comunes si fuera necesario.
    # Por ahora lo dejamos para Gemini o que se infiera del número de vuelo en el futuro.
    nil
  end

  def extract_airports
    # Buscar códigos IATA (3 letras mayúsculas)
    # Intentamos buscar contexto: FROM/TO, ORIGIN/DESTINATION, etc.
    
    found_codes = @text.scan(/\b[A-Z]{3}\b/).uniq
    valid_codes = found_codes.select { |code| Airport.exists?(iata_code: code) }

    # Heurística simple: si hay 2 códigos válidos, el primero suele ser origen y el segundo destino
    # Esto es muy básico, pero es un punto de partida.
    {
      departure: valid_codes[0],
      arrival: valid_codes[1],
      departure_conf: valid_codes[0] ? "medium" : "low",
      arrival_conf: valid_codes[1] ? "medium" : "low"
    }
  end

  def extract_date
    # Buscamos formatos DD/MM/YYYY, DD-MM-YYYY, DD MMM YYYY
    # 1. Intentar fecha completa
    date_match = @text.match(/\b(\d{1,2})[\/\-\s]([A-Z]{3}|\d{1,2})[\/\-\s](\d{2,4})\b/i)
    
    if date_match
      day = date_match[1]
      month = date_match[2]
      year = date_match[3]
      
      # Normalizar año si es de 2 dígitos
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
        # Fallback si falla el parseo
      end
    end

    # 2. Si no hay fecha completa, buscar día y mes y cruzar con metadata
    day_month_match = @text.match(/\b(\d{1,2})[\/\-\s]([A-Z]{3}|\d{1,2})\b/i)
    if day_month_match && @target_year
      day = day_month_match[1]
      month = day_month_match[2]
      
      begin
        # Intentar con el año objetivo
        estimated_date = Date.parse("#{day} #{month} #{@target_year}")
        
        # Verificar cercanía con full_date (metadata)
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
