source "https://rubygems.org"

gem "rails", "~> 8.1.2"
gem "propshaft"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "tailwindcss-rails"
gem "jbuilder"
gem "bcrypt", "~> 3.1.7"
gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false
gem "image_processing", "~> 1.2"
gem "dotenv-rails", groups: %i[development test]
gem "view_component", "~> 3.10"
gem "pdf-reader", "~> 2.12"

gem "omniauth-google-oauth2", "~> 1.1"
gem "omniauth-apple", "~> 1.3"
gem "omniauth-rails_csrf_protection", "~> 1.0"

gem "sidekiq"

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails", "~> 6.1"
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.2"
end

group :test do
  gem "shoulda-matchers", "~> 7.0"
end

group :development do
  gem "web-console"
end



gem "redis", "~> 5.4"
