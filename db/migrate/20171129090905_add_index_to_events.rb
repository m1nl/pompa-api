class AddIndexToEvents < ActiveRecord::Migration[5.1]
  def change
    add_index :events, [:victim_id, :reported_date]
  end
end
