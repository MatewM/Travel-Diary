class CreateAirports < ActiveRecord::Migration[8.1]
  def change
    create_table :airports do |t|
      t.string :iata_code, null: false
      t.string :name, null: false
      t.string :city
      t.references :country, null: false, foreign_key: true

      t.timestamps
    end

    add_index :airports, :iata_code, unique: true
  end
end
