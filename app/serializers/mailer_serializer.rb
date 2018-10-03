class MailerSerializer < ApplicationSerializer
  attributes :id, :name, :host, :port, :username, :password, :sender_email, :sender_name, :ignore_certificate, :per_minute, :burst
  has_many :scenarios

  def password
    object.password.blank? ? nil : MailersController::PASSWORD_MAGIC
  end

  def links
    links = super
    links.merge!({ :scenarios => Rails.application.routes
      .url_helpers.url_for(:controller => :scenarios, :action => :index,
        :only_path => true, filter: { :mailer_id => object.id }) })
  end
end
