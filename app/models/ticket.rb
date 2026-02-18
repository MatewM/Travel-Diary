# frozen_string_literal: true

class Ticket < ApplicationRecord
  belongs_to :user
  belongs_to :trip, optional: true
  belongs_to :departure_country, class_name: "Country", optional: true
  belongs_to :arrival_country, class_name: "Country", optional: true

  enum :status, {
    pending_parse: "pending_parse",
    parsed: "parsed",
    manual: "manual",
    error: "error"
  }

  validates :departure_airport, format: { with: /\A[A-Z]{3}\z/, message: "debe ser un código IATA de 3 letras mayúsculas" }, allow_blank: true
  validates :arrival_airport, format: { with: /\A[A-Z]{3}\z/, message: "debe ser un código IATA de 3 letras mayúsculas" }, allow_blank: true
  validate :arrival_after_departure

  private

  def arrival_after_departure
    return unless departure_datetime.present? && arrival_datetime.present?

    errors.add(:arrival_datetime, :before_departure, message: "no puede ser anterior a la fecha/hora de salida") if arrival_datetime <= departure_datetime
  end
end
