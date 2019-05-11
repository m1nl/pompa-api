module Defaults
  extend ActiveSupport::Concern

  included do
    after_initialize :apply_default_values
  end

  def apply_default_values
    self.class.defaults.each do |attribute, param|
      next unless self.send(attribute).nil?
      value = param.respond_to?(:call) ? param.call(self) : param
      self[attribute] = value
    rescue ActiveModel::MissingAttributeError
      next
    end
  end

  class_methods do
    def default(attribute, value = nil, &block)
      defaults[attribute] = value
      defaults[attribute] = block if block_given?
    end

    def defaults
      @defaults ||= {}
    end
  end
end
