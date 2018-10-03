class ReferenceGroupInTarget < ActiveRecord::Migration[5.0]
  def change
    add_reference :targets, :group, :null => false, index: true
    add_foreign_key :targets, :groups, on_delete: :cascade
  end
end
