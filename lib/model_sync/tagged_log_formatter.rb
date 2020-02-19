# frozen_string_literal: true

require "logger"
require "active_support/logger"

module ModelSync
  class TaggedLogFormatter
    include ActiveSupport::TaggedLogging::Formatter

    def initialize(formatter = nil)
      @formatter = formatter || ::Logger::Formatter.new
    end

    def call(severity, time, program_name, message)
      message = "[#{ModelSync.current_name}] #{message}" if !ModelSync
        .current_name.blank?
      message = "[TID-#{ModelSync.tid}] #{message}" if !ModelSync
        .tid.blank?
      message = "[#{ModelSync::TAG}] #{message}"

      @formatter.call(severity, time, program_name, message)
    end
  end
end
