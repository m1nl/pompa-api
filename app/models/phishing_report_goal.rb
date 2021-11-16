class PhishingReportGoal < ApplicationRecord
  belongs_to :template, :required => true
  belongs_to :goal, :required => true
end
