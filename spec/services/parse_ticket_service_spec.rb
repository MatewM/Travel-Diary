# frozen_string_literal: true

require "rails_helper"

RSpec.describe ParseTicketService do
  let(:user)    { create(:user) }
  let(:ticket)  { create(:ticket, user: user, status: :manual) }

  # Bypass the file-required validation by faking the status column directly
  before do
    ticket.update_column(:status, "pending_parse")
  end

  # Gemini response fixture — all fields with high confidence
  let(:high_confidence_json) do
    {
      "flight_number"      => "IB3456",
      "airline"            => "Iberia",
      "departure_airport"  => "MAD",
      "arrival_airport"    => "LHR",
      "departure_datetime" => "2025-06-01T10:00:00Z",
      "arrival_datetime"   => "2025-06-01T12:00:00Z",
      "passenger_name"     => "Jane Doe",
      "confidence"         => {
        "flight_number"      => "high",
        "airline"            => "high",
        "departure_airport"  => "high",
        "arrival_airport"    => "high",
        "departure_datetime" => "high",
        "arrival_datetime"   => "high"
      }
    }.to_json
  end

  # Fixture with an unknown airport (not in DB)
  let(:unknown_airport_json) do
    {
      "flight_number"      => "AB999",
      "airline"            => "AirX",
      "departure_airport"  => "XYZ",   # not in DB
      "arrival_airport"    => "LHR",
      "departure_datetime" => "2025-07-01T08:00:00Z",
      "arrival_datetime"   => "2025-07-01T10:00:00Z",
      "passenger_name"     => "Jane Doe",
      "confidence"         => {
        "flight_number"      => "high",
        "airline"            => "high",
        "departure_airport"  => "high",
        "arrival_airport"    => "high",
        "departure_datetime" => "high",
        "arrival_datetime"   => "high"
      }
    }.to_json
  end

  # Fixture with inverted dates
  let(:inverted_dates_json) do
    {
      "flight_number"      => "VY1234",
      "airline"            => "Vueling",
      "departure_airport"  => "MAD",
      "arrival_airport"    => "LHR",
      "departure_datetime" => "2025-06-01T14:00:00Z",
      "arrival_datetime"   => "2025-06-01T10:00:00Z",  # before departure!
      "passenger_name"     => "Jane Doe",
      "confidence"         => {
        "flight_number"      => "high", "airline" => "high",
        "departure_airport"  => "high", "arrival_airport" => "high",
        "departure_datetime" => "high", "arrival_datetime" => "high"
      }
    }.to_json
  end

  # Stub file-system and Ticket.find so no real file access or API call is needed.
  # Use plain doubles: instance_double rejects content_type because ActiveStorage::Attachment
  # delegates it to Blob rather than defining it as an instance method.
  before do
    fake_blob       = double("ActiveStorage::Blob", key: "fake_key")
    fake_attachment = double("ActiveStorage::Attachment",
                             content_type: "application/pdf",
                             blob: fake_blob)

    allow(ticket).to receive_message_chain(:original_files, :first)
      .and_return(fake_attachment)

    # The service calls Ticket.find(ticket_id) which produces a new AR instance.
    # Returning the test's `ticket` ensures our stubs apply inside the service.
    allow(Ticket).to receive(:find).with(ticket.id).and_return(ticket)

    allow(ActiveStorage::Blob).to receive_message_chain(:service, :path_for)
      .and_return("/tmp/fake_ticket.pdf")
  end

  describe ".call" do
    context "with high-confidence Gemini response and known airports" do
      let!(:madrid) { create(:airport, :madrid) }
      let!(:london) { create(:airport, :london) }

      it "sets status :auto_verified and persists extracted data" do
        allow(GeminiClient).to receive(:parse_document).and_return(high_confidence_json)

        result = described_class.call(ticket.id)

        expect(result[:success]).to be true
        expect(result[:confidence_level]).to eq(:high)

        ticket.reload
        expect(ticket.status).to eq("auto_verified")
        expect(ticket.flight_number).to eq("IB3456")
        expect(ticket.departure_airport).to eq("MAD")
        expect(ticket.arrival_airport).to eq("LHR")
        expect(ticket.departure_country).to eq(madrid.country)
        expect(ticket.arrival_country).to eq(london.country)
      end
    end

    context "when the departure airport is not found in the DB" do
      let!(:london) { create(:airport, :london) }

      it "sets status :needs_review or :manual_required and departure_country as nil" do
        allow(GeminiClient).to receive(:parse_document).and_return(unknown_airport_json)

        result = described_class.call(ticket.id)

        expect(result[:success]).to be true

        ticket.reload
        expect(ticket.status).to be_in(%w[needs_review manual_required])
        expect(ticket.departure_country).to be_nil
      end
    end

    context "when Gemini returns invalid JSON" do
      it "sets status :error and returns success: false" do
        allow(GeminiClient).to receive(:parse_document).and_return("NOT JSON }{")

        result = described_class.call(ticket.id)

        expect(result[:success]).to be false
        expect(result[:error]).to be_present

        ticket.reload
        expect(ticket.status).to eq("error")
        expect(ticket.parsed_data["error"]).to be_present
      end
    end

    context "when arrival datetime is before departure datetime" do
      let!(:madrid) { create(:airport, :madrid) }
      let!(:london) { create(:airport, :london) }

      it "sets status :needs_review (date incoherence)" do
        allow(GeminiClient).to receive(:parse_document).and_return(inverted_dates_json)

        result = described_class.call(ticket.id)

        expect(result[:success]).to be true

        ticket.reload
        expect(ticket.status).to be_in(%w[needs_review manual_required])
      end
    end
  end
end
