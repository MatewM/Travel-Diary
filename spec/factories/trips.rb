FactoryBot.define do
  factory :trip do
    association :user
    association :destination_country, factory: :country
    departure_date { Date.today }
    arrival_date { Date.today + 5 }
    transport_type { "flight" }
    has_boarding_pass { false }
    manually_entered { false }
  end
end
