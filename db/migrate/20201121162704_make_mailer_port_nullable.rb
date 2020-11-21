class MakeMailerPortNullable < ActiveRecord::Migration[6.0]
  def up
    change_column :mailers, :port, :integer, :null => true
  end

  def down
    change_column :mailers, :port, :integer, :null => false
  end
end
