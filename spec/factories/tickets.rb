FactoryBot.define do
  factory :ticket do
    association :user
    # status :manual no requiere archivo adjunto — facilita tests de modelo
    status { "manual" }
  end
end
