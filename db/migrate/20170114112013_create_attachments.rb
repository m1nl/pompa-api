class CreateAttachments < ActiveRecord::Migration[5.0]
  def change
    create_table :attachments do |t|
      t.citext :name, :null => false
      t.string :filename, :null => false
      t.references :template, index: true, :null => false
      t.references :resource, :null => false
      t.timestamps
    end

    add_index :attachments, [:template_id, :name], unique: true
    add_foreign_key :attachments, :templates, on_delete: :cascade
    add_foreign_key :attachments, :resources, on_delete: :restrict
  end
end
