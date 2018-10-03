class ScenarioReport < ApplicationRecord
  belongs_to :scenario

  self.primary_key = 'scenario_id'

  protected
    def readonly?
      true
    end
end
