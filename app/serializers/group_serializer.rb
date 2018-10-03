class GroupSerializer < ApplicationSerializer
  attributes :id, :name, :description
  has_many :targets

  def links
    links = super
    links.merge!({ :targets => Rails.application.routes
      .url_helpers.url_for(:controller => :targets, :action => :index,
        :only_path => true, filter: { :group_id => object.id }) })
  end
end
