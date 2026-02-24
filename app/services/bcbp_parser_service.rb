gem 'zxing_cpp'
require 'zxing'

class BcbpParserService
  class << self
    def decode_from_file(filepath)
      return nil unless filepath.match?(/\.(jpg|jpeg|png)$/i)

      begin
        ZXing.decode(filepath.to_s)
      rescue StandardError
        nil
      end
    end

    def parse(bcbp_string)
      return nil if bcbp_string.blank?
      bcbp_string = bcbp_string.strip

      return nil unless bcbp_string.start_with?("M")

      # Expresión regular robusta que busca independientemente del padding:
      # Origen(3) + Destino(3) + Aerolínea(3) + Vuelo(5) + DíaJuliano(3)
      regex = /([A-Z]{3})([A-Z]{3})([A-Z0-9\s]{3})([A-Z0-9\s]{5})(\d{3})/
      match = bcbp_string.match(regex)

      if match
        # match[0] es la cadena encontrada. 
        # El nombre termina unos 8 caracteres antes del aeropuerto de origen (1 para ETI + 7 para PNR)
        match_start = bcbp_string.index(match[0])
        name_end = [match_start - 8, 2].max
        
        {
          passenger_name: bcbp_string[2...name_end].to_s.strip,
          departure_airport: match[1].strip.upcase,
          arrival_airport: match[2].strip.upcase,
          airline: match[3].strip,
          flight_number: match[4].strip,
          julian_day: match[5].to_i,
          year_digit: nil # Forzamos nil para que use la fecha del archivo original como fallback
        }
      else
        # Fallback al estándar rígido original por si la regex falla
        return nil unless bcbp_string.length >= 48
        {
          passenger_name: bcbp_string[2, 20].strip,
          departure_airport: bcbp_string[30, 3].strip.upcase,
          arrival_airport: bcbp_string[33, 3].strip.upcase,
          airline: bcbp_string[36, 3].strip,
          flight_number: bcbp_string[39, 5].strip,
          julian_day: bcbp_string[44, 3].to_i,
          year_digit: nil
        }
      end
    end

    def resolve_year(year_digit, reference_year = Date.today.year)
      ref_digit = reference_year % 10
      diff = (ref_digit - year_digit) % 10
      reference_year - diff
    end

    def process_decoded_string(raw_string, capture_date_str = nil)
      parsed = parse(raw_string)
      return nil unless parsed

      flight_date, date_status = resolve_flight_date(parsed, capture_date_str)
      return nil unless flight_date || date_status

      {
        source:            :bcbp_barcode,
        departure_airport: parsed[:departure_airport],
        arrival_airport:   parsed[:arrival_airport],
        flight_number:     parsed[:flight_number],
        airline:           parsed[:airline],
        passenger_name:    parsed[:passenger_name],
        flight_date:       flight_date,
        date_status:       date_status
      }
    end

    def extract(filepath, capture_date_str = nil)
      return nil unless filepath.match?(/\.(jpg|jpeg|png)$/i)

      raw = decode_from_file(filepath)
      return nil unless raw

      process_decoded_string(raw, capture_date_str) # Llama al nuevo método
    end

    private

    def resolve_flight_date(parsed, capture_date_str)
      if parsed[:year_digit]
        # Caso 1: El BCBP incluye el último dígito del año -> automáticamente autoverified
        year = resolve_year(parsed[:year_digit])
        flight_date = Date.ordinal(year, parsed[:julian_day])
        date_status = :autoverified
      elsif capture_date_str
        # Caso 2: El BCBP no incluye el año, usar metadata de capture_date
        capture_year = capture_date_str[0, 4].to_i
        flight_date = Date.ordinal(capture_year, parsed[:julian_day]) rescue nil
        
        if flight_date
          # Convertir capture_date_str a Date para comparación
          capture_date = Date.parse(capture_date_str) rescue nil
          
          if capture_date
            # Calcular diferencia absoluta en días entre capture_date y flight_date
            days_diff = (capture_date - flight_date).to_i.abs
            
            # Si la captura fue dentro de ±3 días del vuelo -> autoverified
            # Si no -> needs_review
            date_status = (days_diff <= 3) ? :autoverified : :needs_review
          else
            date_status = :needs_review
          end
        else
          date_status = nil
        end
      else
        flight_date = nil
        date_status = nil
      end

      [flight_date, date_status]
    end
  end
end