class CreateTargets < ActiveRecord::Migration[5.0]
  def change
    create_table :targets do |t|
      t.string :first_name, :null => false
      t.string :last_name, :null => false
      t.string :gender
      t.string :department
      t.citext :email, :null => false
      t.text :comment
      t.timestamps
    end
  end
end
