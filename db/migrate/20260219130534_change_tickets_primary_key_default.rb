class ChangeTicketsPrimaryKeyDefault < ActiveRecord::Migration[7.1]
  def change
    change_column_default :tickets, :id, from: -> { "gen_random_uuid()" }, to: nil
  end
end
