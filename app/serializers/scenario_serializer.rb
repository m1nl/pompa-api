class ScenarioSerializer < ApplicationSerializer
  attributes :id, :model, :campaign_id, :template_id, :mailer_id, :group_id
  belongs_to :campaign
  belongs_to :template
  belongs_to :mailer
  belongs_to :group
  has_many :victims
  has_one :report

  def links
    links = super
    links.merge!({ :campaign => Rails.application.routes
      .url_helpers.url_for(:controller => :campaigns, :action => :show,
        :only_path => true, :id => object.campaign_id) })
    links.merge!({ :template => Rails.application.routes
      .url_helpers.url_for(:controller => :templates, :action => :show,
        :only_path => true, :id => object.template_id) })
    links.merge!({ :mailer => Rails.application.routes
      .url_helpers.url_for(:controller => :mailers, :action => :show,
        :only_path => true, :id => object.mailer_id) })
    links.merge!({ :group => Rails.application.routes
      .url_helpers.url_for(:controller => :groups, :action => :show,
        :only_path => true, :id => object.group_id) }) if object.group_id
    links.merge!({ :victims => Rails.application.routes
      .url_helpers.url_for(:controller => :victims, :action => :index,
        :only_path => true, :filter => { :scenario_id => object.id }) })
    links.merge!({ :report => Rails.application.routes
      .url_helpers.url_for(:controller => :scenario_reports, :action => :show,
        :only_path => true, :id => object.id) })
    links.merge!({ :events => Rails.application.routes
      .url_helpers.url_for(:controller => :events, :action => :index,
        :only_path => true, :filter => { :victim => { :scenario_id => object.id } }) })
  end
end
