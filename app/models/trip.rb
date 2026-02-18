# frozen_string_literal: true

class Trip < ApplicationRecord
  belongs_to :user
  belongs_to :origin_country, class_name: "Country", optional: true
  belongs_to :destination_country, class_name: "Country"
  has_many :tickets, dependent: :destroy

  enum :transport_type, {
    flight: "flight",
    train: "train",
    car: "car",
    ship: "ship",
    other: "other",
    unknown: "unknown"
  }

  validates :departure_date, presence: true
  validates :arrival_date, presence: true
  validates :destination_country, presence: true
  validate :arrival_not_before_departure

  private

  def arrival_not_before_departure
    return unless departure_date.present? && arrival_date.present?

    errors.add(:arrival_date, :before_departure, message: "no puede ser anterior a la fecha de salida") if arrival_date < departure_date
  end
end
