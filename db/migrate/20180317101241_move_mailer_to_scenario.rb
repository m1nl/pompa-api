class MoveMailerToScenario < ActiveRecord::Migration[5.1]
  def up
    add_reference :scenarios, :mailer, index: true
    add_foreign_key :scenarios, :mailers, on_delete: :restrict

    execute <<-EOS
      UPDATE scenarios AS s
        SET mailer_id = t.mailer_id
        FROM templates t
        WHERE s.template_id = t.id
    EOS

    remove_foreign_key :templates, :mailers
    remove_reference :templates, :mailer, index: true

    change_column :scenarios, :mailer_id, :integer, null: false
  end

  def down
    add_reference :templates, :mailer, index: true
    add_foreign_key :templates, :mailers, on_delete: :restrict

    execute <<-EOS
      UPDATE templates AS t
        SET mailer_id = s.mailer_id
        FROM scenarios s
        WHERE s.template_id = t.id
    EOS

    remove_foreign_key :scenarios, :mailers
    remove_reference :scenarios, :mailer, index: true

    change_column :templates, :mailer_id, :integer, null: false
  end
end
