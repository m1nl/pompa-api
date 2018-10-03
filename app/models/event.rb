require 'time'

class Event < ApplicationRecord
  include Defaults
  include Pageable

  belongs_to :victim, required: true
  belongs_to :goal, required: true

  validates :reported_date, presence: true

  default :reported_date, proc { Time.current }
end
