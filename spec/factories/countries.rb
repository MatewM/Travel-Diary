FactoryBot.define do
  factory :country do
    sequence(:name) { |n| "Country #{n}" }
    sequence(:code) { |n| [ (65 + (n / 26) % 26).chr, (65 + n % 26).chr ].join }
    continent { "Europe" }
    max_days_allowed { 183 }
  end
end
