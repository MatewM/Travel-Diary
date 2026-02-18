class CreateTrips < ActiveRecord::Migration[8.0]
  def change
    create_table :trips, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: true
      t.references :origin_country, foreign_key: { to_table: :countries }, index: true
      t.references :destination_country, null: false, foreign_key: { to_table: :countries }, index: true
      t.date :departure_date, null: false
      t.date :arrival_date, null: false
      t.string :title
      t.string :transport_type, default: "flight"
      t.boolean :has_boarding_pass, default: false
      t.boolean :manually_entered, default: false
      t.text :notes

      t.timestamps
    end

    add_index :trips, [ :user_id, :departure_date ]
    add_index :trips, :departure_date
  end
end
