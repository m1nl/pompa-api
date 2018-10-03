class GoalSerializer < ApplicationSerializer
  attributes :id, :name, :description, :code, :score, :template_id
  belongs_to :template

  def links
    links = super
    links.merge!({ :template => Rails.application.routes
      .url_helpers.url_for(:controller => :templates, :action => :show,
        :only_path => true, :id => object.template_id) })
  end
end
