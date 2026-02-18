FactoryBot.define do
  factory :ticket do
    association :user
    status { "pending_parse" }
  end
end
