class TargetQuicksearch < ApplicationRecord
  belongs_to :target

  self.primary_key = 'target_id'
  self.table_name = 'target_quicksearch'

  scope :search, ->(term) {
    wildcard_terms = term.split(' ').collect { |t| "%#{t}%" }
    where(arel_table[:query].matches_all(wildcard_terms))
  }

  protected
    def readonly?
      true
    end
end
