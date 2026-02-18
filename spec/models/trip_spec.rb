require "rails_helper"

RSpec.describe Trip, type: :model do
  describe "factory" do
    it "crea un trip válido" do
      expect(build(:trip)).to be_valid
    end
  end

  describe "validaciones de fechas" do
    it "falla si departure_date es posterior a arrival_date" do
      trip = build(:trip, departure_date: Date.today + 5, arrival_date: Date.today)
      expect(trip).not_to be_valid
      expect(trip.errors[:arrival_date]).to be_present
    end

    it "es válido cuando departure_date == arrival_date (viaje en el mismo día)" do
      expect(build(:trip, departure_date: Date.today, arrival_date: Date.today)).to be_valid
    end
  end

  describe "validaciones de presencia" do
    it "falla sin destination_country" do
      trip = build(:trip, destination_country: nil)
      expect(trip).not_to be_valid
      expect(trip.errors[:destination_country]).to be_present
    end

    it "falla sin departure_date" do
      expect(build(:trip, departure_date: nil)).not_to be_valid
    end

    it "falla sin arrival_date" do
      expect(build(:trip, arrival_date: nil)).not_to be_valid
    end
  end
end
