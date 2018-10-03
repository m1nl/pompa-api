class CampaignSerializer < ApplicationSerializer
  attributes :id, :name, :description, :model, :start_date, :started_date, :finish_date, :finished_date, :state
  has_many :scenarios

  def links
    links = super
    links.merge!({ :scenarios => Rails.application.routes
      .url_helpers.url_for(:controller => :scenarios, :action => :index,
        :only_path => true, :filter => { :campaign_id => object.id }) })
  end
end
