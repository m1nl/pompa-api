class CreateScenarios < ActiveRecord::Migration[5.0]
  def change
    create_table :scenarios do |t|
      t.references :campaign, index: true, :null => false
      t.references :template, :null => false
      t.references :group
      t.json :model
      t.timestamps
    end

    add_foreign_key :scenarios, :campaigns, on_delete: :cascade
    add_foreign_key :scenarios, :templates, on_delete: :restrict
    add_foreign_key :scenarios, :groups, on_delete: :nullify
  end
end
