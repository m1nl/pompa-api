module Pompa
  module Worker
    module Const
      ANONYMOUS = 'anonymous'.freeze
      CLASS = 'Class'.freeze

      STARTED = 'started'.freeze
      FINISHED = 'finished'.freeze
      CANCELLED = 'cancelled'.freeze
      RESPAWN = 'respawn'.freeze
      RUNNING = 'running'.freeze
      INITIALIZING = 'initializing'.freeze

      WORKER_STATE_CHANGE = 'worker_state_change'.freeze

      SUCCESS = 'success'.freeze
      FAILED = 'failed'.freeze
      INVALID = 'invalid'.freeze
      ERROR = 'error'.freeze
      TIMEOUT = 'timeout'.freeze
      FILE = 'file'.freeze

      TIMEOUT_RESPONSE = { :result => { :status => TIMEOUT } }.freeze
      INVALID_RESPONSE = { :result => { :status => INVALID } }.freeze

      CANCEL_NORMAL = 1.freeze
      CANCEL_DISCARD = 2.freeze

      PING = { :ping => true }.freeze

      TIMEOUT_QUANTUM = 1.seconds

      REDIS_OPTS = [:pool, :redis].freeze

      def queue_timeout
        @queue_timeout ||= Rails.configuration.pompa
          .worker.queue_timeout.seconds
      end

      def refill_interval
        @refill_interval ||= Rails.configuration.pompa
          .worker.refill_interval.seconds
      end

      def expiry_timeout
        @expiry_timeout ||= Rails.configuration.pompa
          .worker.expiry_timeout.seconds
      end
    end
  end
end
