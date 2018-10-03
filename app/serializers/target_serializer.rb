class TargetSerializer < ApplicationSerializer
  attributes :id, :first_name, :last_name, :display_name, :gender, :department, :email, :comment, :group_id

  belongs_to :group

  def links
    links = super
    links.merge!({ :group => Rails.application.routes
      .url_helpers.url_for(:controller => :groups, :action => :show,
        :only_path => true, :id => object.group_id) })
  end
end
