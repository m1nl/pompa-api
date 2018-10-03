class CreateTemplates < ActiveRecord::Migration[5.0]
  def change
    create_table :templates do |t|
      t.citext :name, :null => false
      t.text :description
      t.string :sender_email
      t.string :sender_name
      t.string :base_url
      t.string :landing_url
      t.string :report_url
      t.string :static_resource_url
      t.string :dynamic_resource_url
      t.string :subject
      t.text :plaintext
      t.text :html
      t.references :mailer, foreign_key: true, :null => false
      t.timestamps
    end

    add_index :templates, :name, unique: true
  end
end
