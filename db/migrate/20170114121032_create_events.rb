class CreateEvents < ActiveRecord::Migration[5.0]
  def change
    create_table :events do |t|
      t.references :victim, :null => false, index: true
      t.references :goal, :null => false, index: true
      t.datetime :reported_date, :null => false
      t.json :data
      t.timestamps
    end

    add_foreign_key :events, :victims, on_delete: :cascade
    add_foreign_key :events, :goals, on_delete: :restrict
  end
end
