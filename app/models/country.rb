# frozen_string_literal: true

class Country < ApplicationRecord
  has_many :airports, dependent: :destroy

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true, length: { is: 2 }
  validates :max_days_allowed, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :min_days_required, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
