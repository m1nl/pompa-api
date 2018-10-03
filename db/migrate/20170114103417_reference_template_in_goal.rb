class ReferenceTemplateInGoal < ActiveRecord::Migration[5.0]
  def change
    add_reference :goals, :template, :null => false, index: true
    add_foreign_key :goals, :templates, on_delete: :cascade
    add_index :goals, [:name, :template_id], unique: true
    add_index :goals, :code, unique: true
  end
end
