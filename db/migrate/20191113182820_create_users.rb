class CreateUsers < ActiveRecord::Migration[6.0]
  def change
    create_table :users do |t|
      t.citext :client_id, :null => false
      t.string :roles, :array => true, :default => []
      t.jsonb :properties
      t.timestamps
    end

    add_index :users, :client_id, unique: true
  end
end
