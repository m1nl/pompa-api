class AddTransformsToResource < ActiveRecord::Migration[5.1]
  def change
    add_column :resources, :transforms, :json
  end
end
