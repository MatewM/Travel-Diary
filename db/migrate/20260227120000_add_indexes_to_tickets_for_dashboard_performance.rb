class AddIndexesToTicketsForDashboardPerformance < ActiveRecord::Migration[8.1]
  def change
    add_index :tickets, :departure_datetime
    add_index :tickets, :created_at
  end
end
