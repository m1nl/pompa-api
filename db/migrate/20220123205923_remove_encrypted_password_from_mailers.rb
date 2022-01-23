class RemoveEncryptedPasswordFromMailers < ActiveRecord::Migration[7.0]
  def change
    remove_column :mailers, :encrypted_password, :string
    remove_column :mailers, :encrypted_password_iv, :string
  end
end
