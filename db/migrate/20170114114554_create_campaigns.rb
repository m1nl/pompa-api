class CreateCampaigns < ActiveRecord::Migration[5.0]
  def change
    create_table :campaigns do |t|
      t.citext :name, :null => false
      t.text :description
      t.string :state, :null => false
      t.integer :state_order, :null => false
      t.datetime :start_date
      t.datetime :started_date
      t.datetime :finish_date
      t.datetime :finished_date
      t.string :jid
      t.json :model
      t.timestamps
    end

    add_index :campaigns, :name, unique: true
    add_index :campaigns, :state_order
  end
end
