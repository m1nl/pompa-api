require 'awesome_print'
require 'colorize'
require 'pompa/utils'

module Pompa
  module MultiLogger
    class AwesomeLogger
      OPTIONS = { multiline: false }.freeze

      def initialize(logger)
        @logger = logger || Rails.logger
      end

      def method_missing(m, *args, &block)
        @logger.send(m, *args, &block)
      end

      def debug(message = nil, opts = {})
        return if !logger.debug?
        message ||= yield if block_given?
        logger.debug(prepare(message, opts))
      end

      def info(message = nil, opts = {})
        return if !logger.info?
        message ||= yield if block_given?
        logger.info(prepare(message, opts))
      end

      def warn(message = nil, opts = {})
        return if !logger.warn?
        message ||= yield if block_given?
        logger.warn(prepare(message, opts))
      end

      def error(message = nil, opts = {})
        return if !logger.error?
        message ||= yield if block_given?
        logger.error(prepare(message, opts))
      end

      def fatal(message = nil, opts = {})
        return if !logger.fatal?
        message ||= yield if block_given?
        logger.fatal(prepare(message, opts))
      end

      def unknown(message = nil, opts = {})
        return if !logger.unknown?
        message ||= yield if block_given?
        logger.unknown(prepare(message, opts))
      end

      def backtrace(o, severity = :error)
        o = o.backtrace if o.is_a?(Exception)

        Rails.backtrace_cleaner.clean(o).each do |b|
          public_send(severity) {"\t#{b.red}"}
        end
      end

      private
        def prepare(message, opts)
          no_truncate = !!opts.delete(:no_truncate)
          options = OPTIONS.merge(opts)

          ( Array(message).map do |v|
            next v if v.is_a?(String)

            v = Pompa::Utils.truncate(v) unless no_truncate
            v.ai(options)
          end ).join
        end

        def logger
          @logger
        end
    end
  end
end
