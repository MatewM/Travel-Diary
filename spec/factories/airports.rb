FactoryBot.define do
  factory :airport do
    association :country
    sequence(:iata_code) { |n| format("A%02d", n % 100).upcase.ljust(3, "Z")[0, 3] }
    sequence(:name)      { |n| "Airport #{n}" }
    city { "City" }

    trait :madrid do
      iata_code { "MAD" }
      name      { "Adolfo Suárez Madrid-Barajas" }
      city      { "Madrid" }
    end

    trait :london do
      iata_code { "LHR" }
      name      { "London Heathrow" }
      city      { "London" }
    end
  end
end
