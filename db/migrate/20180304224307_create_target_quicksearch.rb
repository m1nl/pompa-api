class CreateTargetQuicksearch < ActiveRecord::Migration[5.1]
  def up
    execute <<-EOS
      CREATE VIEW target_quicksearch AS
        (SELECT v.id as target_id,
                (COALESCE(v.first_name, '') ||
                 COALESCE(v.last_name, '') ||
                 COALESCE(v.email, '') ||
                 COALESCE(v.gender, '') ||
                 COALESCE(v.department, '') ||
                 COALESCE(v.comment, '')) AS query
         FROM targets v)
    EOS

    execute <<-EOS
      CREATE INDEX idx_target_quicksearch
      ON targets
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
      DROP INDEX idx_target_quicksearch
    EOS

    execute <<-EOS
      DROP VIEW target_quicksearch
    EOS
  end
end
