# frozen_string_literal: true

$stdout.sync = true

require 'pathname'
require 'singleton'
require 'optparse'

require 'model_sync'
require 'model_sync/launcher'

module ModelSync
  class CLI
    include Singleton

    CLI = 'cli'
    DEVELOPMENT = 'development'

    attr_accessor :launcher
    attr_accessor :environment

    def parse(args = ARGV)
      setup_options(args)
      initialize_logger
    end

    def run
      boot_system

      self_read, self_write = IO.pipe
      sigs = %w[INT TERM TTIN TSTP]
      sigs.each do |sig|
        trap sig do
          self_write.puts(sig)
        end
      rescue ArgumentError
        logger.error("Signal #{sig} not supported")
      end

      logger.info("Running in #{RUBY_DESCRIPTION}")

      launch(self_read)
    end

    def launch(self_read)
      if environment == DEVELOPMENT && $stdout.tty?
        logger.info('Starting processing, hit Ctrl-C to stop')
      end

      @launcher = ModelSync::Launcher.new(options)

      begin
        launcher.run

        while (readable_io = IO.select([self_read]))
          signal = readable_io.first[0].gets.strip
          handle_signal(signal)
        end
      rescue Interrupt
        logger.info('Shutting down')
        launcher.stop
        logger.info('Bye!')

        exit(0)
      end
    end

    SIGNAL_HANDLERS = {
      # Ctrl-C in terminal
      'INT' => ->(cli) { raise Interrupt },
      # TERM is the signal that the process must exit.
      'TERM' => ->(cli) { raise Interrupt },
      'TTIN' => ->(cli) {
        Thread.list.each do |t|
          next if t[:tid].blank?

          ModelSync.logger.warn("Thread TID-#{t[:tid]} #{t[:name]}")
          if t.backtrace
            ModelSync.logger.backtrace(t.backtrace, :warn)
          else
            ModelSync.logger.warn('<no backtrace available>')
          end
        end
      },
    }
    UNHANDLED_SIGNAL_HANDLER = ->(cli) { logger.info('No signal handler registered, ignoring') }
    SIGNAL_HANDLERS.default = UNHANDLED_SIGNAL_HANDLER

    def handle_signal(sig)
      logger.debug("Got #{sig} signal")
      SIGNAL_HANDLERS[sig].call(self)
    end

    private
      def rails_root
        @rails_root ||= Pathname.new('../..').expand_path(File.dirname(__FILE__))
      end

      def logger
        ModelSync.logger
      end

      def options
        ModelSync.options
      end

      def set_environment(cli_env)
        @environment = cli_env || ENV['RAILS_ENV'] || ENV['RACK_ENV'] || DEVELOPMENT
      end

      def setup_options(args)
        opts = parse_options(args)
        options.merge!(opts)

        set_environment(options[:environment])
      end

      def boot_system
        Thread.current[:name] = CLI
        $0 = ModelSync::NAME

        require File.expand_path("#{rails_root}/config/boot.rb")
        require File.expand_path("#{rails_root}/config/environment.rb")

        Rails.application.eager_load!

        if !$stdout.tty?
          ModelSync.logger = Rails.logger
        end

        logger.info("Booted Rails #{Rails.version} application in #{environment} environment")
      end

      def parse_options(argv)
        opts = {}
        @parser = option_parser(opts)
        @parser.parse!(argv)
        opts
      end

      def option_parser(opts)
        parser = OptionParser.new { |o|
          o.on('-e', '--environment ENV', 'Application environment') do |arg|
            opts[:environment] = arg
          end

          o.on('-c', '--consumers CONSUMERS', 'Number of consumer threads') do |arg|
            opts[:consumers] = arg.to_i
          end

          o.on('-n', '--no-producer', 'Don\'t run producer thread') do |arg|
            opts[:producer] = arg
          end

          o.on('-v', '--verbose', 'Print more verbose output') do |arg|
            opts[:verbose] = arg
          end
        }
  
        parser.banner = 'model-sync [options]'
        parser.on_tail('-h', '--help', 'Show help') do
          puts parser
          exit(1)
        end
  
        parser
      end

      def initialize_logger
        logger.level = Logger::DEBUG if !!options[:verbose]
      end
  end
end
