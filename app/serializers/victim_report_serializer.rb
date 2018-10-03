class VictimReportSerializer < ApplicationSerializer
  attributes :victim_id, :goals, :total_score, :max_score
  belongs_to :victim

  def links
    links = super
    links.merge!({ :victim => Rails.application.routes
      .url_helpers.url_for(:controller => :victims, :action => :show,
        :only_path => true, :id => object.victim_id) })
  end
end
