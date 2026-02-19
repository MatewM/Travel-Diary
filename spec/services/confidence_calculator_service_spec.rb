# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConfidenceCalculatorService do
  # Helper to build a complete valid parsed_data hash
  def valid_data(overrides = {})
    {
      "flight_number"      => "IB3456",
      "airline"            => "Iberia",
      "departure_airport"  => "MAD",
      "arrival_airport"    => "LHR",
      "departure_datetime" => "2025-06-01T10:00:00Z",
      "arrival_datetime"   => "2025-06-01T12:00:00Z",
      "passenger_name"     => "John Doe",
      "confidence"         => {
        "flight_number"      => "high",
        "airline"            => "high",
        "departure_airport"  => "high",
        "arrival_airport"    => "high",
        "departure_datetime" => "high",
        "arrival_datetime"   => "high"
      }
    }.merge(overrides)
  end

  let!(:madrid) { create(:airport, :madrid) }
  let!(:london) { create(:airport, :london) }

  describe ".call" do
    context "when all fields are valid and airports exist in DB" do
      it "returns level :high and status :auto_verified with no issues" do
        result = described_class.call(valid_data)

        expect(result[:level]).to eq(:high)
        expect(result[:status]).to eq(:auto_verified)
        expect(result[:issues]).to be_empty
      end
    end

    context "when 1 critical field is nil" do
      it "returns level :medium and status :needs_review" do
        data   = valid_data("departure_airport" => nil)
        result = described_class.call(data)

        expect(result[:level]).to eq(:medium)
        expect(result[:status]).to eq(:needs_review)
        expect(result[:issues]).to include(:departure_airport)
      end
    end

    context "when 3 critical fields are nil" do
      it "returns level :low and status :manual_required" do
        data = valid_data(
          "departure_airport"  => nil,
          "arrival_airport"    => nil,
          "departure_datetime" => nil
        )
        result = described_class.call(data)

        expect(result[:level]).to eq(:low)
        expect(result[:status]).to eq(:manual_required)
      end
    end

    context "when an airport has an invalid IATA format" do
      it "returns level :medium (format issue counts as 1 issue)" do
        data   = valid_data("departure_airport" => "madrid")  # lowercase, too long
        result = described_class.call(data)

        expect(result[:level]).to eq(:medium)
        expect(result[:issues]).to include(:departure_airport)
      end
    end

    context "when arrival datetime is before departure datetime" do
      it "flags :arrival_datetime and returns level :medium" do
        data = valid_data(
          "departure_datetime" => "2025-06-01T14:00:00Z",
          "arrival_datetime"   => "2025-06-01T12:00:00Z"
        )
        result = described_class.call(data)

        expect(result[:level]).to eq(:medium)
        expect(result[:issues]).to include(:arrival_datetime)
      end
    end

    context "when an airport is not found in the DB" do
      it "flags the missing airport field" do
        data   = valid_data("arrival_airport" => "XYZ")
        result = described_class.call(data)

        expect(result[:issues]).to include(:arrival_airport)
      end
    end

    context "when Gemini declares low confidence on a field" do
      it "includes that field in issues" do
        data = valid_data("confidence" => valid_data["confidence"].merge("flight_number" => "low"))
        result = described_class.call(data)

        expect(result[:issues]).to include(:flight_number)
      end
    end
  end
end
