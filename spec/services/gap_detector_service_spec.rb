require 'rails_helper'

RSpec.describe GapDetectorService do
  let(:user) { create(:user) }
  let(:spain) { create(:country, name: 'Spain', code: 'ES') }
  let(:france) { create(:country, name: 'France', code: 'FR') }
  let(:portugal) { create(:country, name: 'Portugal', code: 'PT') }

  describe '.call' do
    context 'cuando no hay trips ese año' do
      it 'devuelve array vacío' do
        result = described_class.call(user, 2024)
        expect(result).to be_empty
      end
    end

    context 'construye fila de estancia correcta para un trip' do
      let!(:trip) do
        create(:trip,
               user: user,
               origin_country: spain,
               destination_country: france,
               departure_date: Date.new(2024, 6, 1),
               arrival_date: Date.new(2024, 6, 2),
               has_boarding_pass: true,
               manually_entered: false)
      end

      it 'crea fila correcta con end_date nil para último trip' do
        result = described_class.call(user, 2024)

        expect(result.size).to eq(1)
        row = result.first

        expect(row[:type]).to eq(:trip)
        expect(row[:country]).to eq(france)
        expect(row[:start_date]).to eq(Date.new(2024, 6, 2))
        expect(row[:end_date]).to be_nil
        expect(row[:days]).to eq((Date.today - Date.new(2024, 6, 2)).to_i + 1)
        expect(row[:trip_id]).to eq(trip.id)
        expect(row[:has_boarding_pass]).to eq(true)
        expect(row[:manually_entered]).to eq(false)
        expect(row[:origin_country]).to eq(spain)
      end
    end

    context 'detecta gap temporal entre dos trips no consecutivos' do
      let!(:trip1) do
        create(:trip,
               user: user,
               origin_country: spain,
               destination_country: france,
               departure_date: Date.new(2024, 6, 1),
               arrival_date: Date.new(2024, 6, 2))
      end

      let!(:trip2) do
        create(:trip,
               user: user,
               origin_country: france,
               destination_country: spain,
               departure_date: Date.new(2024, 6, 5), # Gap de 2 días (3-4 junio)
               arrival_date: Date.new(2024, 6, 6))
      end

      it 'inserta fila de gap temporal' do
        result = described_class.call(user, 2024)

        expect(result.size).to eq(3) # trip1 + gap + trip2

        gap_row = result[1]
        expect(gap_row[:type]).to eq(:gap)
        expect(gap_row[:gap_type]).to eq(:temporal)
        expect(gap_row[:gap_message]).to include("Hay 2 días entre")
        expect(gap_row[:start_date]).to eq(Date.new(2024, 6, 3))
        expect(gap_row[:end_date]).to eq(Date.new(2024, 6, 5))
        expect(gap_row[:days]).to eq(2)
      end
    end

    context 'detecta gap geográfico si destination[N] ≠ origin[N+1]' do
      let!(:trip1) do
        create(:trip,
               user: user,
               origin_country: spain,
               destination_country: france,
               departure_date: Date.new(2024, 6, 1),
               arrival_date: Date.new(2024, 6, 2))
      end

      let!(:trip2) do
        create(:trip,
               user: user,
               origin_country: portugal, # Diferente a destination de trip1
               destination_country: spain,
               departure_date: Date.new(2024, 6, 4),
               arrival_date: Date.new(2024, 6, 5))
      end

      it 'inserta fila de gap geográfico con prioridad sobre temporal' do
        result = described_class.call(user, 2024)

        expect(result.size).to eq(3) # trip1 + gap + trip2

        gap_row = result[1]
        expect(gap_row[:type]).to eq(:gap)
        expect(gap_row[:gap_type]).to eq(:geographic)
        expect(gap_row[:gap_message]).to include("Saliste de France pero no hay registro")
        expect(gap_row[:origin_country]).to eq(portugal)
      end
    end

    context 'inserta inherited_trip como primera fila si había trip activo del año anterior' do
      let!(:previous_year_trip) do
        create(:trip,
               user: user,
               origin_country: spain,
               destination_country: france,
               departure_date: Date.new(2024, 12, 25),
               arrival_date: Date.new(2023, 12, 20), # Llegó en 2023
               has_boarding_pass: true,
               manually_entered: true)
      end

      let!(:current_year_trip) do
        create(:trip,
               user: user,
               origin_country: france,
               destination_country: spain,
               departure_date: Date.new(2024, 6, 1),
               arrival_date: Date.new(2024, 6, 2))
      end

      it 'inserta inherited_trip al inicio' do
        result = described_class.call(user, 2024)

        expect(result.size).to eq(2) # inherited_trip + current_trip

        inherited_row = result.first
        expect(inherited_row[:type]).to eq(:inherited_trip)
        expect(inherited_row[:country]).to eq(france)
        expect(inherited_row[:start_date]).to eq(Date.new(2024, 1, 1))
        expect(inherited_row[:end_date]).to eq(Date.new(2024, 5, 31)) # departure_date - 1
        expect(inherited_row[:days]).to eq(151) # 1 enero a 31 mayo
        expect(inherited_row[:trip_id]).to eq(previous_year_trip.id)
        expect(inherited_row[:has_boarding_pass]).to eq(true)
        expect(inherited_row[:manually_entered]).to eq(true)
      end
    end

    context 'el último trip tiene end_date nil si no hay siguiente trip ese año' do
      let!(:trip) do
        create(:trip,
               user: user,
               origin_country: spain,
               destination_country: france,
               departure_date: Date.new(2024, 6, 1),
               arrival_date: Date.new(2024, 6, 2))
      end

      it 'tiene end_date nil para el último trip' do
        result = described_class.call(user, 2024)

        trip_row = result.first
        expect(trip_row[:end_date]).to be_nil
        expect(trip_row[:days]).to eq((Date.today - Date.new(2024, 6, 2)).to_i + 1)
      end
    end

    context 'calcula days correctamente (arrival_date inclusivo)' do
      let!(:trip) do
        create(:trip,
               user: user,
               origin_country: spain,
               destination_country: france,
               departure_date: Date.new(2024, 6, 1),
               arrival_date: Date.new(2024, 6, 2))
      end

      let!(:next_trip) do
        create(:trip,
               user: user,
               origin_country: france,
               destination_country: spain,
               departure_date: Date.new(2024, 6, 5),
               arrival_date: Date.new(2024, 6, 6))
      end

      it 'calcula días correctamente incluyendo arrival_date' do
        result = described_class.call(user, 2024)

        trip_row = result.first
        # Del 2 junio al 4 junio (departure_date siguiente - 1) = 3 días
        expect(trip_row[:days]).to eq(3)
        expect(trip_row[:start_date]).to eq(Date.new(2024, 6, 2))
        expect(trip_row[:end_date]).to eq(Date.new(2024, 6, 4))
      end
    end
  end
end
