class AddPasswordToMailer < ActiveRecord::Migration[7.0]
  def change
    add_column :mailers, :password, :string
  end
end
