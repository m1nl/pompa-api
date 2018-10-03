class CreateGroups < ActiveRecord::Migration[5.0]
  def change
    create_table :groups do |t|
      t.citext :name, :null => false
      t.text :description
      t.timestamps
    end

    add_index :groups, :name, unique: true
  end
end
