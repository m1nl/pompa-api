class ChangeModelToJsonbInModels < ActiveRecord::Migration[5.1]
  def up
    change_column :campaigns, :model, :jsonb
    change_column :scenarios, :model, :jsonb
  end

  def down
    change_column :scenarios, :model, :json
    change_column :campaigns, :model, :json
  end
end
