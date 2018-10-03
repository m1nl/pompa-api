class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, :with => :record_not_found
  rescue_from ActiveRecord::RecordNotUnique, :with => :record_not_unique
  rescue_from ActiveRecord::RecordInvalid, :with => :record_invalid
  rescue_from ActiveRecord::InvalidForeignKey, :with => :record_referenced

  if Rails.env.production?
    rescue_from ActiveRecord::ConfigurationError, :with => :query_invalid
    rescue_from ActiveRecord::StatementInvalid, :with => :query_invalid
  end

  NOT_FOUND = 'not found'.freeze
  NOT_UNIQUE = 'not unique'.freeze
  INVALID = 'invalid'.freeze
  REFERENCED = 'referenced'.freeze

  private
    def record_not_found(error)
      render :json => { :error => { :record => [NOT_FOUND] } },
        :status => :not_found
    end

    def record_not_unique(error)
      render :json => { :error => { :record => [NOT_UNIQUE] } },
        :status => :unprocessable_entity
    end

    def record_invalid(error)
      render :json => { :error => { :record => [INVALID] } },
        :status => :unprocessable_entity
    end

    def record_referenced(error)
      render :json => { :error => { :record => [REFERENCED] } },
        :status => :unprocessable_entity
    end

    def query_invalid(error)
      render :json => { :error => { :query => [INVALID] } },
        :status => :unprocessable_entity
    end
end
