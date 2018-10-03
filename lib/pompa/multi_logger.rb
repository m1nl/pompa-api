require 'pompa/multi_logger/awesome_logger'

module Pompa
  module MultiLogger
    def self.extended(base)
      if base.is_a?(ActiveSupport::Logger)
        @logger = base
      elsif base.respond_to?(:logger)
        @logger = base.send(:logger)
      else
        @logger = Rails.logger
      end
    end

    def multi_logger
      @logger ||= send(:logger) || Rails.logger
      @multi_logger ||= AwesomeLogger.new(@logger)
    end

    def backtrace(e)
      multi_logger.backtrace(e)
    end
  end
end
