class ApplicationController < ActionController::API
  include ErrorHandlers

  include Authenticatable
  include Pundit

  if Rails.configuration.pompa.authentication.enabled
    before_action :authenticate
    around_action :add_current_user_log_tag
  end

  if Rails.env.production?
    rescue_from ActiveRecord::ConfigurationError, :with => :query_invalid
    rescue_from ActiveRecord::StatementInvalid, :with => :query_invalid
  end

  rescue_from ActiveRecord::RecordNotFound, :with => :record_not_found
  rescue_from ActiveRecord::RecordNotUnique, :with => :record_not_unique
  rescue_from ActiveRecord::InvalidForeignKey, :with => :record_referenced
  rescue_from ActiveRecord::RecordInvalid, :with => :record_invalid

  rescue_from Pundit::NotAuthorizedError, :with => :forbidden_error
end
