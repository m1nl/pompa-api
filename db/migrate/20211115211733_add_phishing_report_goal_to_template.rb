class AddPhishingReportGoalToTemplate < ActiveRecord::Migration[6.1]
  def change
    add_reference :templates, :phishing_report_goal, null: true, index: false
    add_foreign_key :templates, :goals, column: "phishing_report_goal_id", on_delete: :nullify
  end
end
