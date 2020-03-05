# frozen_string_literal: true

require 'logger'
require 'socket'
require 'securerandom'
require 'concurrent'

require 'pompa/multi_logger'

module ModelSync
  NAME = 'Pompa model-sync'
  TAG = 'model-sync'

  DEFAULTS = {
    :consumers => Concurrent.processor_count,
    :producer => true,
    :verbose => false,
  }

  CHANNEL = 'model_sync'

  QUEUE = 'ModelSync:message_queue'
  PROCESS_QUEUE = 'ModelSync:message_process_queue'
  PRODUCER_LOCK = 'ModelSync:producer_lock'

  TIMEOUT = 5
  LOCK_TIMEOUT = 10

  CREATE = 'create'
  DELETE = 'delete'
  UPDATE = 'update'

  OPERATIONS = [CREATE, DELETE, UPDATE].freeze

  UnsupportedDatabaseError = Class.new(StandardError)

  def self.options
    @options ||= DEFAULTS.dup
  end

  def self.options=(opts)
    @options = opts
  end

  def self.logger
    @logger ||= ::Logger.new(STDOUT, level: ::Logger::INFO).tap do |l|
      l.formatter = ModelSync::LogFormatter.new
      l.extend(Pompa::MultiLogger)
    end
  end

  def self.logger=(logger)
    if logger.nil?
      self.logger.level = ::Logger::FATAL
      return self.logger
    end

    @logger = logger.tap do |l|
      l.extend(Pompa::MultiLogger)
    end
  end

  def self.tid
    Thread.current['tid'] ||= (Thread.current.object_id ^ Process.pid).to_s(36)
  end

  def self.current_name
    Thread.current['name'] || ''
  end

  def self.pid
    Process.pid
  end

  def self.hostname
    Socket.gethostname
  end

  def self.process_nonce
    @@process_nonce ||= SecureRandom.hex(6)
  end

  def self.identity
    @@identity ||= '#{hostname}:#{::Process.pid}:#{process_nonce}'
  end
end

