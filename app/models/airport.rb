# frozen_string_literal: true

class Airport < ApplicationRecord
  belongs_to :country

  validates :iata_code, presence: true, uniqueness: true,
                        format: { with: /\A[A-Z]{3}\z/, message: "must be exactly 3 uppercase letters" }
  validates :name, presence: true
end
