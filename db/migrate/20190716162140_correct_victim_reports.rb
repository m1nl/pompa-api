class CorrectVictimReports < ActiveRecord::Migration[6.0]
  def up
    execute <<-EOS
      DROP VIEW victim_reports
    EOS

    execute <<-EOS
      CREATE VIEW victim_reports AS
        (WITH g AS
          (SELECT DISTINCT ON (v.id, g.id)
                  v.id AS victim_id,
                  g.id AS goal_id,
                  g.name,
                  g.description,
                  g.score,
                  g.code,
                  (e.reported_date IS NOT NULL)::BOOLEAN AS hit,
                  e.reported_date,
                  e.data
           FROM victims v
           JOIN scenarios s ON v.scenario_id = s.id
           JOIN goals g ON g.template_id = s.template_id
           LEFT JOIN events e ON e.victim_id = v.id AND e.goal_id = g.id
           ORDER BY v.id ASC,
                    g.id ASC,
                    e.reported_date ASC)
        SELECT v.id AS victim_id,
               array_to_json(array_remove(array_agg(row_to_json(g)::JSONB - 'victim_id'), null))::JSONB AS goals,
               COALESCE(SUM(g.score * g.hit::INT), 0) as total_score,
               COALESCE(SUM(g.score), 0) AS max_score
        FROM victims v
        LEFT JOIN g ON g.victim_id = v.id
        GROUP BY v.id
        ORDER BY v.id ASC)
    EOS
  end

  def down
    execute <<-EOS
      DROP VIEW victim_reports
    EOS

    execute <<-EOS
      CREATE VIEW victim_reports AS
        (WITH g AS
          (SELECT DISTINCT ON (v.id, g.score, g.id)
                  v.id AS victim_id,
                  g.id AS goal_id,
                  g.name,
                  g.description,
                  g.score,
                  g.code,
                  (e.reported_date IS NOT NULL)::BOOLEAN AS hit,
                  e.reported_date,
                  e.data
           FROM victims v
           JOIN scenarios s ON v.scenario_id = s.id
           JOIN templates t ON s.template_id = t.id
           JOIN goals g ON g.template_id = t.id
           LEFT JOIN events e ON e.victim_id = v.id AND e.goal_id = g.id
           ORDER BY v.id ASC,
                    g.score DESC,
                    g.id ASC,
                    e.reported_date ASC)
        SELECT v.id AS victim_id,
               array_to_json(array_remove(array_agg(row_to_json(g)::JSONB - 'victim_id'), null))::JSONB AS goals,
               COALESCE(SUM(g.score * g.hit::INT), 0) as total_score,
               COALESCE(SUM(g.score), 0) AS max_score
        FROM victims v
        LEFT JOIN g ON g.victim_id = v.id
        GROUP BY v.id
        ORDER BY v.id ASC)
    EOS
  end
end
