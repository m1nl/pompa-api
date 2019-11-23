class CreateUsers < ActiveRecord::Migration[6.0]
  def change
    create_table :users do |t|
      t.citext :client_id, :null => false
      t.string :properties, :array => true, :default => []
      t.string :roles, :array => true, :default => []
      t.timestamps
    end

    add_index :users, :client_id, unique: true
  end
end
