class CreateMailers < ActiveRecord::Migration[5.0]
  def change
    create_table :mailers do |t|
      t.citext :name, :null => false
      t.string :host, :null => false
      t.integer :port, :null => false
      t.string :username
      t.string :encrypted_password
      t.string :encrypted_password_iv
      t.string :sender_email
      t.string :sender_name
      t.boolean :ignore_certificate
      t.integer :per_minute
      t.integer :burst
      t.string :jid
      t.timestamps
    end

    add_index :mailers, :name, unique: true
  end
end
