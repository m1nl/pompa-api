require 'active_support/concern'

module NullifyBlanks
  extend ActiveSupport::Concern

  included do
    before_validation :nullify_blanks
  end

  def nullify_blanks
    self.class.blanks.each do |a|
      self[a] = nil if self[a].blank?
    end
  end

  class_methods do
    def nullify_blanks(*attributes)
      blanks.push(*attributes)
    end

    def blanks
      @blanks ||= []
    end
  end
end
