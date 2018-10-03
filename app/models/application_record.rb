require 'pompa'

class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
end
