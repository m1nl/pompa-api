class CreateGoals < ActiveRecord::Migration[5.0]
  def change
    create_table :goals do |t|
      t.citext :name, :null => false
      t.text :description
      t.integer :score, :null => false
      t.citext :code, :null => false
      t.timestamps
    end
  end
end
