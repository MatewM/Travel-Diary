class AddOriginalFileMetadataToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :original_file_metadata, :jsonb
  end
end
