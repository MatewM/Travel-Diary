# frozen_string_literal: true

class Ticket < ApplicationRecord
  belongs_to :user
  belongs_to :trip, optional: true
  belongs_to :departure_country, class_name: "Country", optional: true
  belongs_to :arrival_country, class_name: "Country", optional: true

  has_many_attached :original_files
  before_create :assign_uuid

  ALLOWED_CONTENT_TYPES = %w[application/pdf image/jpeg image/png].freeze
  MAX_FILE_SIZE = 10.megabytes

  enum :status, {
    pending_parse:    "pending_parse",
    processing:       "processing",
    auto_verified:    "auto_verified",
    needs_review:     "needs_review",
    manual_required:  "manual_required",
    parsed:           "parsed",
    manual:           "manual",
    error:            "error"
  }

  validates :departure_airport, format: { with: /\A[A-Z]{3}\z/, message: "debe ser un código IATA de 3 letras mayúsculas" }, allow_blank: true
  validates :arrival_airport, format: { with: /\A[A-Z]{3}\z/, message: "debe ser un código IATA de 3 letras mayúsculas" }, allow_blank: true

  validate :original_files_required, unless: :manual?
  validate :original_files_content_type, if: -> { original_files.attached? }
  validate :original_files_size, if: -> { original_files.attached? }
  validate :arrival_after_departure

  private


# Añadir al bloque private (al final del archivo)
  def assign_uuid
     self.id ||= SecureRandom.uuid
  end

  def original_files_required
    errors.add(:original_files, :blank) unless original_files.attached?
  end

  def original_files_content_type
    original_files.each do |file|
      unless file.content_type.in?(ALLOWED_CONTENT_TYPES)
        errors.add(:original_files, "#{file.filename}: debe ser PDF, JPG o PNG (recibido: #{file.content_type})")
      end
    end
  end

  def original_files_size
    original_files.each do |file|
      if file.byte_size > MAX_FILE_SIZE
        errors.add(:original_files, "#{file.filename}: no puede superar los 10MB")
      end
    end
  end

  def arrival_after_departure
    return unless departure_datetime.present? && arrival_datetime.present?

    # Solo penalizar si llega ANTES de salir (no si son iguales — cuando solo tenemos el día)
    errors.add(:arrival_datetime, :before_departure, message: "no puede ser anterior a la fecha/hora de salida") if arrival_datetime < departure_datetime
  end
end
