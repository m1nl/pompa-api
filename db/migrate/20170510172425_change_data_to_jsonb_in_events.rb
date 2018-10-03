class ChangeDataToJsonbInEvents < ActiveRecord::Migration[5.0]
  def up
    change_column :events, :data, :jsonb
  end

  def down
    change_column :events, :data, :json
  end
end
