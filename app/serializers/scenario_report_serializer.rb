class ScenarioReportSerializer < ApplicationSerializer
  attributes :scenario_id, :goals, :victims
  belongs_to :scenario

  def links
    links = super
    links.merge!({ :scenario => Rails.application.routes
      .url_helpers.url_for(:controller => :scenarios, :action => :show,
        :only_path => true, :id => object.scenario_id) })
  end
end
