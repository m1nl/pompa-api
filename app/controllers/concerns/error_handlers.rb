require 'pompa/multi_logger'

module ErrorHandlers
  extend ActiveSupport::Concern

  included do
    include Pompa::MultiLogger
  end

  WWW_AUTHENTICATE_HEADER = 'WWW-Authenticate'.freeze
  BEARER = 'Bearer'.freeze

  NOT_FOUND = 'is not found'.freeze
  NOT_UNIQUE = 'is not unique'.freeze
  INVALID = 'is invalid'.freeze
  REFERENCED = 'is referenced or has invalid reference'.freeze

  protected
    def record_not_found(error = nil)
      render :json => { :errors => { :record => [NOT_FOUND] } },
        :status => :not_found
    end

    def record_not_unique(error = nil)
      render :json => { :errors => { :record => [NOT_UNIQUE] } },
        :status => :unprocessable_entity
    end

    def record_referenced(error = nil)
      render :json => { :errors => { :record => [REFERENCED] } },
        :status => :unprocessable_entity
    end

    def record_invalid(error = nil)
      render :json => { :errors => { :record => [INVALID] } },
        :status => :unprocessable_entity

      if !error.nil?
        multi_logger.error{"Error in #{self.class.name}, #{error.class}: #{error.message}"}
        multi_logger.backtrace(error)
      end
    end

    def query_invalid(error = nil)
      render :json => { :errors => { :query => [INVALID] } },
        :status => :unprocessable_entity

      if !error.nil?
        multi_logger.error{"Error in #{self.class.name}, #{error.class}: #{error.message}"}
        multi_logger.backtrace(error)
      end
    end

    def routing_error(error = nil)
      head :not_found

      if !error.nil?
        multi_logger.error{"Error in #{self.class.name}, #{error.class}: #{error.message}"}
        multi_logger.backtrace(error)
      end
    end

    def forbidden_error(error = nil)
      head :forbidden

      if !error.nil?
        multi_logger.error{"Error in #{self.class.name}, #{error.class}: #{error.message}"}
        multi_logger.backtrace(error)
      end
    end

    def unauthorized_error(error = nil)
      response.headers[WWW_AUTHENTICATE_HEADER] = BEARER
      head :unauthorized

      if !error.nil?
        multi_logger.error{"Error in #{self.class.name}, #{error.class}: #{error.message}"}
        multi_logger.backtrace(error)
      end
    end
end
