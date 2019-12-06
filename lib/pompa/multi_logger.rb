require 'pompa/multi_logger/awesome_logger'

module Pompa
  module MultiLogger
    def logger
      return super if defined?(super)

      @logger ||= self if self.is_a?(ActiveSupport::Logger)
      @logger ||= Rails.logger
    end

    def multi_logger
      @multi_logger ||= AwesomeLogger.new(logger)
    end

    def backtrace(e)
      multi_logger.backtrace(e)
    end
  end
end
