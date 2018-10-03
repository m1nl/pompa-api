class CreateScenarioReports < ActiveRecord::Migration[5.0]
  def up
    execute <<-EOS
      CREATE VIEW scenario_reports AS
        (WITH g AS
          (SELECT s.id AS scenario_id,
                  g.id AS goal_id,
                  g.name,
                  g.description,
                  g.score,
                  g.code,
                  COUNT(DISTINCT v.id)::INT AS count
           FROM scenarios s
           JOIN goals g ON g.template_id = s.template_id
           LEFT JOIN events e ON e.goal_id = g.id
           LEFT JOIN victims v ON v.id = e.victim_id AND v.scenario_id = s.id
           GROUP BY s.id,
                    g.id
           ORDER BY g.score DESC,
                    g.id ASC),
              v AS
          (SELECT r.*, (r.pending + r.queued + r.sent + r.error)::INT AS total
           FROM
             (SELECT scenario_id,
                     COALESCE(pending, 0) AS pending,
                     COALESCE(queued, 0) AS queued,
                     COALESCE(sent, 0) AS sent,
                     COALESCE(error, 0) AS error
              FROM crosstab('SELECT s.id as scenario_id, v.state, count(DISTINCT v.id)::INT FROM scenarios s LEFT JOIN victims v ON v.scenario_id = s.id GROUP BY s.id, v.state ORDER BY s.id', 'VALUES (''pending''), (''queued''), (''sent''), (''error'')') AS v(scenario_id INT, pending INT, queued INT, sent INT, error INT)) r)
        SELECT s.id AS scenario_id,
               array_to_json(array_remove(array_agg(row_to_json(g)::JSONB - 'scenario_id'), NULL))::JSONB AS goals,
               row_to_json(v)::JSONB - 'scenario_id' AS victims
        FROM scenarios s
        LEFT JOIN g g ON s.id = g.scenario_id
        LEFT JOIN v v ON s.id = v.scenario_id
        GROUP BY s.id,
                 v.*
        ORDER BY s.id ASC)
    EOS
  end

  def down
    execute <<-EOS
      DROP VIEW scenario_reports
    EOS
  end
end
