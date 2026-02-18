class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email, null: false
      t.string :name, null: false
      t.string :provider, null: false, default: "email"
      t.string :uid
      t.string :password_digest

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, %i[provider uid]
  end
end
