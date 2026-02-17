class Trip < ApplicationRecord
  belongs_to :user
  has_many_attached :tickets

  validates :destination, :start_date, :end_date, :country, presence: true
end
