require 'pompa/multi_logger'

class ApplicationController < ActionController::API
  include Pompa::MultiLogger

  if Rails.env.production?
    rescue_from ActiveRecord::ConfigurationError, :with => :query_invalid
    rescue_from ActiveRecord::StatementInvalid, :with => :query_invalid
  end

  rescue_from ActiveRecord::RecordNotFound, :with => :record_not_found
  rescue_from ActiveRecord::RecordNotUnique, :with => :record_not_unique
  rescue_from ActiveRecord::RecordInvalid, :with => :record_invalid
  rescue_from ActiveRecord::InvalidForeignKey, :with => :record_referenced

  NOT_FOUND = 'is not found'.freeze
  NOT_UNIQUE = 'is not unique'.freeze
  INVALID = 'is invalid'.freeze
  REFERENCED = 'is referenced'.freeze

  protected
    def record_not_found(error = nil)
      render :json => { :errors => { :record => [NOT_FOUND] } },
        :status => :not_found
    end

    def record_not_unique(error = nil)
      render :json => { :errors => { :record => [NOT_UNIQUE] } },
        :status => :unprocessable_entity
    end

    def record_invalid(error = nil)
      render :json => { :errors => { :record => [INVALID] } },
        :status => :unprocessable_entity
    end

    def record_referenced(error = nil)
      render :json => { :errors => { :record => [REFERENCED] } },
        :status => :unprocessable_entity
    end

    def query_invalid(error = nil)
      render :json => { :errors => { :query => [INVALID] } },
        :status => :unprocessable_entity

      if !error.nil
        multi_logger.error{"Error in #{self.class.name}, #{error.class}: #{error.message}"}
        multi_logger.backtrace(error)
      end
    end
end
