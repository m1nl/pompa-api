class VictimReport < ApplicationRecord
  belongs_to :victim

  self.primary_key = 'victim_id'

  protected
    def readonly?
      true
    end
end
