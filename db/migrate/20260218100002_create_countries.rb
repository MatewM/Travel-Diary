class CreateCountries < ActiveRecord::Migration[8.1]
  def change
    create_table :countries do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.string :continent
      t.integer :min_days_required
      t.integer :max_days_allowed, default: 183

      t.timestamps
    end

    add_index :countries, :code, unique: true
  end
end
