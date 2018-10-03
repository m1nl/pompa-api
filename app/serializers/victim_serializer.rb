class VictimSerializer < ApplicationSerializer
  attributes :id, :first_name, :last_name, :display_name, :gender, :department, :email, :comment, :code, :state, :sent_date, :message_id, :last_error, :error_count, :scenario_id, :target_id
  belongs_to :scenario
  belongs_to :target
  has_many :events
  has_one :report

  def links
    links = super
    links.merge!({ :scenario => Rails.application.routes
      .url_helpers.url_for(:controller => :scenarios, :action => :show,
        :only_path => true, :id => object.scenario_id) })
    links.merge!( {:target => Rails.application.routes
      .url_helpers.url_for(:controller => :targets, :action => :show,
        :only_path => true, :id => object.target_id) }) if object.target_id
    links.merge!({ :events => Rails.application.routes
      .url_helpers.url_for(:controller => :events, :action => :index,
        :only_path => true, filter: { :victim_id => object.id }) })
    links.merge!({ :report => Rails.application.routes
      .url_helpers.url_for(:controller => :victim_reports, :action => :show,
        :only_path => true, :id => object.id) })
  end
end
