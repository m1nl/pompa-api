class CreateVictimQuicksearch < ActiveRecord::Migration[5.1]
  def up
    execute <<-EOS
      CREATE VIEW victim_quicksearch AS
        (SELECT v.id as victim_id,
                (COALESCE(v.first_name, '') ||
                 COALESCE(v.last_name, '') ||
                 COALESCE(v.email, '') ||
                 COALESCE(v.gender, '') ||
                 COALESCE(v.department, '') ||
                 COALESCE(v.comment, '')) AS query
         FROM victims v)
    EOS

    execute <<-EOS
      CREATE INDEX idx_victim_quicksearch
      ON victims
      USING GIN(
                 (COALESCE(first_name, '') ||
                  COALESCE(last_name, '') ||
                  COALESCE(email, '') ||
                  COALESCE(gender, '') ||
                  COALESCE(department, '') ||
                  COALESCE(comment, '')) gin_trgm_ops)
    EOS
  end

  def down
    execute <<-EOS
      DROP INDEX idx_victim_quicksearch
    EOS

    execute <<-EOS
      DROP VIEW victim_quicksearch
    EOS
  end
end
