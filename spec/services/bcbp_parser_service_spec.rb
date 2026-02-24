require 'rails_helper'

RSpec.describe BcbpParserService do
  describe '.parse' do
    let(:bcbp_string) { "M1GARCIA/JUAN        EABCDEF XPMILHRIB 6048 165 Y" }

    it 'parses the example BCBP string correctly' do
      result = described_class.parse(bcbp_string)

      expect(result).to eq({
        passenger_name: "GARCIA/JUAN        E",
        departure_airport: "PMI",
        arrival_airport: "LHR",
        airline: "IB",
        flight_number: "6048",
        julian_day: 165,
        year_digit: nil
      })
    end

    it 'returns nil for string shorter than 48 characters' do
      short_string = "M1SHORT"
      expect(described_class.parse(short_string)).to be_nil
    end

    it 'returns nil for string not starting with M' do
      invalid_string = "X1GARCIA/JUAN        EABCDEF PMILHRIB 6048 165Y019Y0100 100"
      expect(described_class.parse(invalid_string)).to be_nil
    end
  end

  describe '.resolve_year' do
    it 'resolves year digit 6 with reference year 2026 to 2026' do
      expect(described_class.resolve_year(6, 2026)).to eq(2026)
    end

    it 'resolves year digit 5 with reference year 2026 to 2025' do
      expect(described_class.resolve_year(5, 2026)).to eq(2025)
    end

    it 'resolves year digit 9 with reference year 2026 to 2019' do
      expect(described_class.resolve_year(9, 2026)).to eq(2019)
    end

    it 'resolves year digit 0 with reference year 2026 to 2020' do
      expect(described_class.resolve_year(0, 2026)).to eq(2020)
    end
  end

  describe '.extract' do
    let(:bcbp_string) { "M1GARCIA/JUAN        EABCDEF XPMILHRIB 6048 165 Y" }
    let(:bcbp_string_with_year) { "M1GARCIA/JUAN        EABCDEF XPMILHRIB 6048 1655Y019Y0100 100" }

    before do
      allow(described_class).to receive(:decode_from_file).and_return(bcbp_string)
    end

    it 'returns nil for non-image file extensions' do
      expect(described_class).not_to receive(:decode_from_file)
      expect(described_class.extract('document.pdf')).to be_nil
    end

    it 'returns correct data when year_digit is nil and capture_date_str is provided' do
      result = described_class.extract('image.jpg', '2025-06-14')

      expect(result).to eq({
        source: :bcbp_barcode,
        departure_airport: "PMI",
        arrival_airport: "LHR",
        flight_number: "6048",
        airline: "IB",
        passenger_name: "GARCIA/JUAN        E",
        flight_date: Date.new(2025, 6, 14),
        date_status: :autoverified  # Cambio: ahora debería ser autoverified porque capture_date = flight_date
      })
    end

    it 'returns autoverified when capture_date is within 3 days after flight_date' do
      # Julian day 165 = 14 de junio, capture_date = 16 de junio (2 días después)
      result = described_class.extract('image.jpg', '2025-06-16')

      expect(result[:date_status]).to eq(:autoverified)
      expect(result[:flight_date]).to eq(Date.new(2025, 6, 14))
    end

    it 'returns needs_review when capture_date is more than 3 days after flight_date' do
      # Julian day 165 = 14 de junio, capture_date = 20 de junio (6 días después)
      result = described_class.extract('image.jpg', '2025-06-20')

      expect(result[:date_status]).to eq(:needs_review)
      expect(result[:flight_date]).to eq(Date.new(2025, 6, 14))
    end

    it 'returns autoverified when capture_date is within 3 days before flight_date' do
      # Julian day 165 = 14 de junio, capture_date = 12 de junio (2 días antes)
      result = described_class.extract('image.jpg', '2025-06-12')

      expect(result[:date_status]).to eq(:autoverified)
      expect(result[:flight_date]).to eq(Date.new(2025, 6, 14))
    end

    it 'returns needs_review when capture_date is more than 3 days before flight_date' do
      # Julian day 165 = 14 de junio, capture_date = 10 de junio (4 días antes)
      result = described_class.extract('image.jpg', '2025-06-10')

      expect(result[:date_status]).to eq(:needs_review)
      expect(result[:flight_date]).to eq(Date.new(2025, 6, 14))
    end

    it 'returns autoverified when BCBP includes year_digit regardless of capture_date' do
      allow(described_class).to receive(:decode_from_file).and_return(bcbp_string_with_year)
      allow(described_class).to receive(:parse).and_return({
        passenger_name: "GARCIA/JUAN        E",
        departure_airport: "PMI",
        arrival_airport: "LHR",
        airline: "IB",
        flight_number: "6048",
        julian_day: 165,
        year_digit: 5  # Simular que el BCBP incluye el dígito del año
      })

      # Incluso con una capture_date muy diferente, debería ser autoverified
      result = described_class.extract('image.jpg', '2025-12-31')

      expect(result[:date_status]).to eq(:autoverified)
      expect(result[:flight_date]).to eq(Date.new(2025, 6, 14))
    end

    it 'returns autoverified for real case: capture 1 day before flight' do
      # Caso real: vuelo 18/01/25, captura 17/01/25 (1 día antes)
      # Julian day 18 = 18 de enero
      allow(described_class).to receive(:parse).and_return({
        passenger_name: "PASSENGER/NAME",
        departure_airport: "BCN",
        arrival_airport: "MAD",
        airline: "IB",
        flight_number: "1234",
        julian_day: 18,
        year_digit: nil  # Sin año en el BCBP
      })

      result = described_class.extract('image.jpg', '2025-01-17')

      expect(result[:date_status]).to eq(:autoverified)
      expect(result[:flight_date]).to eq(Date.new(2025, 1, 18))
    end
  end
end