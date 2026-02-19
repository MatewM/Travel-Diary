class ChangeActiveStorageAttachmentsRecordIdToUuid < ActiveRecord::Migration[7.0]
  def up
    # 1. Eliminar el índice primero
    remove_index :active_storage_attachments,
      name: "index_active_storage_attachments_uniqueness"

    # 2. Borrar attachments corruptos (record_id es integer, no UUID válido)
    execute <<-SQL
      DELETE FROM active_storage_attachments
      WHERE record_id::text NOT SIMILAR TO 
        '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
    SQL

    # 3. Cambiar el tipo de columna
    change_column :active_storage_attachments, :record_id, :uuid,
      using: 'record_id::text::uuid'

    # 4. Recrear el índice
    add_index :active_storage_attachments,
      [:record_type, :name, :record_id, :blob_id],
      unique: true,
      name: "index_active_storage_attachments_uniqueness"
  end

  def down
    remove_index :active_storage_attachments,
      name: "index_active_storage_attachments_uniqueness"

    change_column :active_storage_attachments, :record_id, :bigint,
      using: 'record_id::text::bigint'
  end
end
