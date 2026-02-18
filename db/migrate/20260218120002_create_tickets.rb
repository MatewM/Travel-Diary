class CreateTickets < ActiveRecord::Migration[8.0]
  def change
    create_table :tickets, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true, index: true
      t.references :trip, type: :uuid, null: true, foreign_key: true, index: true
      t.string :flight_number
      t.string :airline
      t.string :departure_airport
      t.string :arrival_airport
      t.datetime :departure_datetime
      t.datetime :arrival_datetime
      t.references :departure_country, foreign_key: { to_table: :countries }, index: true
      t.references :arrival_country, foreign_key: { to_table: :countries }, index: true
      t.string :status, default: "pending_parse"
      t.jsonb :parsed_data

      t.timestamps
    end

    add_index :tickets, :status
  end
end
