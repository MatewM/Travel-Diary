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

    before do
      allow(described_class).to receive(:decode_from_file).and_return(bcbp_string)
    end

    it 'returns nil for non-image file extensions' do
      expect(described_class).not_to receive(:decode_from_file)
      expect(described_class.extract('document.pdf')).to be_nil
    end

    it 'returns correct data when year_digit is nil and capture_date_str is provided' do
      result = described_class.extract('image.jpg', '2025:06:14')

      expect(result).to eq({
        source: :bcbp_barcode,
        departure_airport: "PMI",
        arrival_airport: "LHR",
        flight_number: "6048",
        airline: "IB",
        passenger_name: "GARCIA/JUAN        E",
        flight_date: Date.new(2025, 6, 14),
        date_status: :needs_review
      })
    end
  end
end