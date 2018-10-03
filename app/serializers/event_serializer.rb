class EventSerializer < ApplicationSerializer
  attributes :id, :reported_date, :data, :goal_id, :victim_id
  belongs_to :goal
  belongs_to :victim

  def links
    links = super
    links.merge!({ :goal => Rails.application.routes
      .url_helpers.url_for(:controller => :goals, :action => :show,
        :only_path => true, :id => object.goal_id) })
    links.merge!({ :victim => Rails.application.routes
      .url_helpers.url_for(:controller => :victims, :action => :show,
        :only_path => true, :id => object.victim_id) })
  end
end
