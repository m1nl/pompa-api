class AttachmentSerializer < ApplicationSerializer
  attributes :id, :name, :filename, :template_id, :resource_id
  belongs_to :template
  belongs_to :resource

  def links
    links = super
    links.merge!({ :template => Rails.application.routes
      .url_helpers.url_for(:controller => :templates, :action => :show,
        :only_path => true, :id => object.template_id) })
    links.merge!({ :resource => Rails.application.routes
      .url_helpers.url_for(:controller => :resources, :action => :show,
        :only_path => true, :id => object.resource_id) })
  end
end
