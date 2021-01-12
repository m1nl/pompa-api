require 'oj'
require 'date'
require 'time'
require 'redis/queue'
require 'pompa/utils'
require 'pompa/multi_logger'
require 'pompa/redis_connection'
require 'pompa/worker/state'
require 'pompa/worker/control'

module Pompa
  module Worker
    include State
    include Control

    include Pompa::MultiLogger

    def perform(opts = {})
      @instance_id = opts[:instance_id]
      @started_at = Time.current

      if !try_claim
        logger.warn("Unable to claim model for #{worker_class_name} " +
          "##{instance_id}. Exiting...")
        return
      end

      if !resync
        logger.error("Unable to load model for #{worker_class_name} " +
          "##{instance_id}. Exiting...")
        return
      end

      self.worker_state = INITIALIZING

      logger.info("Started #{worker_class_name} ##{instance_id} (#{job_id})")

      @worker = ::Worker.create(:id => job_id, :instance_id => instance_id,
        :worker_class_name => worker_class_name,
        :message_queue => message_queue_key_name,
        :started_at => started_at,
        :pool => redis)

      if !worker || !worker.valid?
        logger.error("Unable to register worker. Exiting...")
        return
      end

      @message_queue = Redis::Queue.new(message_queue_key_name,
        message_process_queue_key_name, :redis => Pompa::RedisConnection.get,
        :timeout => queue_timeout, :single => true)

      logger.info("Bound to #{message_queue_key_name}" +
        " with #{queue_timeout}s timeout")

      worker_lock

      self.worker_state = RUNNING

      begin
        response(invoke(opts), opts[:reply_to])
      rescue StandardError => e
        logger.error("Unrecoverable error during invoke " +
          "#{e.class}: #{e.message}. Exiting...")
        multi_logger.backtrace(e)

        self.worker_state = FAILED
        return
      end

      worker_unlock

      loop do
        try_resync
        try_refill

        begin
          response(tick, opts[:reply_to])
        rescue WorkerException => e
          logger.error("Unrecoverable error during ticking " +
            "#{e.class}: #{e.message}. Exiting...")
          multi_logger.backtrace(e)

          self.worker_state = FAILED
          return
        rescue StandardError => e
          logger.error("Ticking failed with #{e.class}: #{e.message}")
          multi_logger.backtrace(e)
        end

        json = message_queue.pop(false, queue_timeout)

        loop do
          try_resync

          result_code = parse_and_process(json)
          message_queue.commit if !json.nil? && result_code != FAILED
          break unless result_code == SUCCESS

          with_worker_lock { json = message_queue.pop(true) }
        end

        worker_lock

        if cancelled?
          self.worker_state = CANCELLED
        elsif respawn? || finished?
          try_refill(:force => true)

          if message_queue.length == 0
            self.worker_state = RESPAWN if respawn?
            self.worker_state = FINISHED if finished?
          end
        end

        break if !running?

        worker_unlock
      end

    rescue WorkerException => e
      logger.error("Unrecoverable error during worker execution " +
        "#{e.class}: #{e.message}. Exiting...")
      multi_logger.backtrace(e)

    ensure
      begin
        try_release

        if worker_state == RESPAWN
          logger.info("Attempting to respawn worker")
          self.class.perform_later(opts)
        end
      ensure
        begin
          try_destroy
        ensure
          worker_unlock
        end
      end
    end

    class WorkerException < StandardError
    end

    class InvalidInstanceException < WorkerException
    end

    class InvalidStateException < WorkerException
    end

    protected
      def claim
        true
      end

      def release
        true
      end

      def resync
        true
      end

      def destroy
        true
      end

      def invoke(opts = {})
        mark
        true
      end

      def tick
        mark
        true
      end

      def process(message)
        logger.debug(message)
      end

      def finished?
        false
      end

      def respawn?
        false
      end

      ###

      def mark
        with_worker_lock(:pool => redis) do |r|
          claim
          redis.with { |r| r.set(last_active_key_name, Time.current.iso8601) }
          worker.mark(:pool => redis) unless worker.nil?
        end

        return true
      end

      def worker_state=(value)
        with_worker_lock(:pool => redis) do |r|
          r.set(worker_state_key_name, value)
          response(result(WORKER_STATE_CHANGE, value, :broadcast => true))
        end

        return value
      end

      def queue_timeout=(value)
        @queue_timeout = value
        logger.info("Queue timeout set to #{queue_timeout}s")
      end

      def idle_for
        Time.current - last_active
      end

      def running?
        self.worker_state == RUNNING
      end

      def started_at
        @started_at
      end

      def worker
        @worker
      end

      def redis
        @redis ||= Pompa::RedisConnection.pool
      end

      def message_queue
        @message_queue
      end

      ###

      def result(status, value = nil, opts = {})
        r = { :status => status }

        if value.is_a?(Hash)
          r.merge!(value)
        elsif !value.nil?
          r.merge!( :value => value )
        end

        return {
          :result => r,
          :expires => expiry_timeout.from_now,
          :origin => {
            :id => self.job_id,
            :name => worker_class_name,
            :instance_id => instance_id,
          }
        }.merge!(opts)
      end

      def response(message, recipient = nil)
        return if !message.is_a?(Hash)

        message[:request_id] ||= Pompa::Utils.uuid

        multi_logger.debug{["Response: ", message]}

        json = message.to_json
        broadcast = !!message[:broadcast]
        recipient ||= message[:reply_to]

        if !recipient.blank?
          redis.with do |r|
            begin
              multi_logger.debug{["Replying with ", Pompa::Utils.truncate(json),
                " to #{recipient}"]}
              r.lpush(recipient, json)
            rescue StandardError => e
              logger.error("Replying failed with #{e.class}: #{e.message}")
              multi_logger.backtrace(e)
            end
          end
        end

        if broadcast
          redis.with do |r|
            r.smembers(subscribe_key_name).each do |s|
              begin
                multi_logger.debug{["Broadcasting ", Pompa::Utils.truncate(json),
                  " to #{s}"]}
                r.lpush(s, json)
              rescue StandardError => e
                logger.error("Broadcasting failed with #{e.class}: #{e.message}")
                multi_logger.backtrace(e)
              end
            end
          end
        end
      end

    private
      def parse_and_process(json)
        if json.blank?
          return INVALID
        end

        multi_logger.debug{["Parsing message: ", Pompa::Utils.truncate(json)]}
        message = nil

        begin
          message = Oj.load(json, symbol_keys: true)
        rescue Oj::ParseError => e
          logger.error("Ignoring invalid message")
          return INVALID
        end

        if !message.is_a?(Hash)
          logger.error("Ignoring invalid message")
          return INVALID
        end

        multi_logger.debug{["Parsed message: ", message]}

        if !message[:expires].nil?
          begin
            expires = Time.iso8601(message[:expires])
            if expires < Time.current
              logger.warn("Ignoring expired message")
              return TIMEOUT
            end
          rescue ArgumentError
            logger.error("Ignoring invalid message")
            return INVALID
          end
        end

        if !!message[:ping]
          result = result(SUCCESS)
        else
          begin
            result = process(message)
            if !result.is_a?(Hash)
              status = result ? SUCCESS : FAILED
              result = result(status, result)
            end
          rescue WorkerException => e
            logger.error("Unrecoverable error during processing " +
              "#{e.class}: #{e.message}. Exiting...")
            multi_logger.backtrace(e)

            result = result(FAILED, "#{e.class.name}: #{e.message}")
            self.worker_state = FAILED
          rescue StandardError => e
            logger.error("Processing failed with #{e.class}: #{e.message}")
            multi_logger.backtrace(e)

            result = result(FAILED, "#{e.class.name}: #{e.message}")
          end
        end

        result[:request_id] ||= message[:request_id]
        response(result, message[:reply_to])

        return result.dig :result, :status
      end

      ###

      def try_claim
        logger.info("Attempting to claim jid")
        claim
      rescue InvalidStateException
        false
      end

      def try_release
        logger.info("Attempting to release jid")
        release
      rescue InvalidStateException
        false
      end

      def try_destroy
        logger.info("Attempting to destroy worker")

        destroy
        worker.destroy(:pool => redis) unless worker.nil?

        if discarded? || finished?
          logger.info("Attempting to discard worker")
          discard
        end

        redis.with { |r| r.del(cancel_key_name) }

        return true
      end

      def try_resync(opts = {})
        return false unless resync_required? || !!opts[:force]

        logger.info("Attempting to resync")

        resync
        redis.with { |r| r.del(resync_key_name) }

        return true
      end

      def try_refill(opts = {})
        return false unless refill_required? || !!opts[:force]

        logger.debug("Attempting to refill message queue")

        message_queue.refill
        @last_refill = Time.current

        return true
      end

      ###

      def cancelled?
        redis.with { |r| r.exists?(cancel_key_name) }
      end

      def discarded?
        redis.with { |r| r.get(cancel_key_name).to_i == CANCEL_DISCARD }
      end

      def resync_required?
        redis.with { |r| r.exists?(resync_key_name) }
      end

      def refill_required?
        @last_refill.nil? || (Time.current - @last_refill) > refill_interval
      end
  end
end
