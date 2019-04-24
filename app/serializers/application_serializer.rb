class ApplicationSerializer < ActiveModel::Serializer
  attribute :links, if: :include_links?

  def links
    links = {}
  end

  def include_links?
    admin_enabled? && !links.blank?
  end

  def admin_enabled?
    self.class.admin_enabled?
  end

  class << self
    def admin_enabled?
      return @admin_enabled unless @admin_enabled.nil?
      @admin_enabled = Rails.configuration.pompa.endpoints.admin
    end
  end
end
