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
      return nil unless bcbp_string&.start_with?("M") && bcbp_string&.length >= 48

      {
        passenger_name: bcbp_string[2, 20].strip,
        departure_airport: bcbp_string[30, 3].strip.upcase,
        arrival_airport: bcbp_string[33, 3].strip.upcase,
        airline: bcbp_string[36, 3].strip,
        flight_number: bcbp_string[39, 5].strip,
        julian_day: bcbp_string[44, 3].to_i,
        year_digit: bcbp_string[47] =~ /\d/ ? bcbp_string[47].to_i : nil
      }
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
        year = resolve_year(parsed[:year_digit])
        flight_date = Date.ordinal(year, parsed[:julian_day])
        date_status = :autoverified
      elsif capture_date_str
        year = capture_date_str[0, 4].to_i
        flight_date = Date.ordinal(year, parsed[:julian_day]) rescue nil
        date_status = flight_date ? :needs_review : nil
      else
        flight_date = nil
        date_status = nil
      end

      [flight_date, date_status]
    end
  end
end