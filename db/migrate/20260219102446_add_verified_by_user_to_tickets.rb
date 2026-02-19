class AddVerifiedByUserToTickets < ActiveRecord::Migration[8.1]
  def change
    # Column already present from a prior migration; this is a no-op guard.
    unless column_exists?(:tickets, :verified_by_user)
      add_column :tickets, :verified_by_user, :boolean, default: false, null: false
    end
  end
end
