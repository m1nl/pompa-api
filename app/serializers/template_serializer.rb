class TemplateSerializer < ApplicationSerializer
  attributes :id, :name, :description, :sender_email, :sender_name, :base_url, :landing_url, :report_url, :static_resource_url, :dynamic_resource_url, :subject, :plaintext, :html
  has_many :goals
  has_many :resources
  has_many :attachments

  def links
    links = super
    links.merge!({ :goals => Rails.application.routes
      .url_helpers.url_for(:controller => :goals, :action => :index,
        :only_path => true, filter: { :template_id => object.id }) })
    links.merge!({ :resources => Rails.application.routes
      .url_helpers.url_for(:controller => :resources, :action => :index,
        :only_path => true, filter: { :template_id => object.id }) })
    links.merge!({ :attachments => Rails.application.routes
      .url_helpers.url_for(:controller => :attachments, :action => :index,
        :only_path => true, filter: { :template_id => object.id }) })
  end
end
