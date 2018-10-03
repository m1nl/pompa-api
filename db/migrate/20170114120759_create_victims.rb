class CreateVictims < ActiveRecord::Migration[5.0]
  def change
    create_table :victims do |t|
      t.string :first_name, :null => false
      t.string :last_name, :null => false
      t.string :gender
      t.string :department
      t.citext :email, :null => false
      t.string :comment
      t.citext :code, :null => false
      t.string :state, :null => false
      t.integer :state_order, :null => false
      t.string :last_error
      t.string :message_id
      t.integer :error_count, :null => false, :default => 0
      t.datetime :sent_date
      t.string :jid
      t.references :scenario, :null => false, :index => true
      t.references :target, :index => true
      t.timestamps
    end

    add_foreign_key :victims, :scenarios, on_delete: :cascade
    add_foreign_key :victims, :targets, on_delete: :nullify

    add_index :victims, :code, unique: true
    add_index :victims, [:scenario_id, :state_order]
  end
end
