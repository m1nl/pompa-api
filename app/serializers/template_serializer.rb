class TemplateSerializer < ApplicationSerializer
  attributes :id, :name, :description, :sender_email, :sender_name, :base_url, :landing_url, :report_url, :static_resource_url, :dynamic_resource_url, :subject, :plaintext, :html, :phishing_report_goal_id
  has_many :goals
  has_many :resources
  has_many :attachments
  belongs_to :phishing_report_goal

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

    if !object.phishing_report_goal_id.nil? then
      links.merge!({ :phishing_report_goal => Rails.application.routes
        .url_helpers.url_for(:controller => :goals, :action => :show,
          :only_path => true, :id => object.phishing_report_goal_id) })
    end

    return links
  end
end
