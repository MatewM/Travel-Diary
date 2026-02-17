FactoryBot.define do
  factory :trip do
    user { nil }
    destination { "MyString" }
    start_date { "2026-02-17" }
    end_date { "2026-02-17" }
    country { "MyString" }
  end
end
