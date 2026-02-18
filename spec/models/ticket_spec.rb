require "rails_helper"

RSpec.describe Ticket, type: :model do
  describe "factory" do
    it "crea un ticket válido (status: manual, sin archivo)" do
      expect(build(:ticket)).to be_valid
    end
  end

  describe "validación de archivos" do
    it "falla sin archivo cuando status es pending_parse" do
      ticket = build(:ticket, status: :pending_parse)
      expect(ticket).not_to be_valid
      expect(ticket.errors[:original_files]).to be_present
    end

    it "es válido sin archivo cuando status es manual" do
      expect(build(:ticket, status: :manual)).to be_valid
    end
  end

  describe "validación de datetimes" do
    it "falla si departure_datetime es posterior a arrival_datetime" do
      ticket = build(
        :ticket,
        departure_datetime: 2.hours.from_now,
        arrival_datetime: 1.hour.from_now
      )
      expect(ticket).not_to be_valid
      expect(ticket.errors[:arrival_datetime]).to be_present
    end

    it "falla si departure_datetime es igual a arrival_datetime" do
      now = Time.current
      ticket = build(:ticket, departure_datetime: now, arrival_datetime: now)
      expect(ticket).not_to be_valid
    end

    it "es válido cuando arrival_datetime es posterior a departure_datetime" do
      ticket = build(
        :ticket,
        departure_datetime: 1.hour.from_now,
        arrival_datetime: 3.hours.from_now
      )
      expect(ticket).to be_valid
    end
  end

  describe "validación de códigos IATA" do
    it "falla con un código IATA de departure_airport inválido" do
      expect(build(:ticket, departure_airport: "mad")).not_to be_valid
      expect(build(:ticket, departure_airport: "MADD")).not_to be_valid
      expect(build(:ticket, departure_airport: "1AB")).not_to be_valid
    end

    it "falla con un código IATA de arrival_airport inválido" do
      expect(build(:ticket, arrival_airport: "bcn")).not_to be_valid
    end

    it "es válido con códigos IATA correctos" do
      expect(build(:ticket, departure_airport: "MAD", arrival_airport: "BCN")).to be_valid
    end

    it "es válido sin código IATA (campo opcional)" do
      expect(build(:ticket, departure_airport: nil, arrival_airport: nil)).to be_valid
    end
  end
end
