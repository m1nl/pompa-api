class VictimQuicksearch < ApplicationRecord
  belongs_to :victim

  self.primary_key = 'victim_id'
  self.table_name = 'victim_quicksearch'

  scope :search, ->(term) {
    wildcard_terms = term.split(' ').collect { |t| "%#{t}%" }
    where(arel_table[:query].matches_all(wildcard_terms))
  }

  protected
    def readonly?
      true
    end
end
