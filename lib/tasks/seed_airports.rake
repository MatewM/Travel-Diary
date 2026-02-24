namespace :db do
  namespace :seed do
    desc 'Importa todos los países y aeropuertos desde OurAirports'
    task airports: :environment do
      load Rails.root.join('db/seeds/countries_and_airports.rb')
    end
  end
end
