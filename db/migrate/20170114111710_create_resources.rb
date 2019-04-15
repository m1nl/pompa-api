class CreateResources < ActiveRecord::Migration[5.0]
  def change
    create_table :resources do |t|
      t.citext :name, :null => false
      t.text :description
      t.string :url
      t.string :content_type
      t.string :extension
      t.boolean :dynamic_url
      t.boolean :render_template
      t.citext :code
      t.references :template, index: true, :null => false
      t.timestamps
    end

    add_foreign_key :resources, :templates, on_delete: :cascade
    add_index :resources, [:template_id, :name], unique: true
    add_index :resources, :code, unique: true
  end
end
