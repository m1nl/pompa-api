# frozen_string_literal: true

require 'socket'

module ModelSync
  class Producer
    NAME = 'producer'

    TCP_KEEPCNT = 5
    TCP_KEEPINTVL = 2
    TCP_KEEPIDLE = 2

    KEEPALIVE_QUERY = 'SELECT 1'

    def initialize
      @done = false
      @mutex = Mutex.new

      @connection = nil
      @socket = nil
    end

    def run
      @mutex.synchronize do
        stop if alive?
        setup_connection

        @thread = Thread.new do
          Thread.current[:name] = NAME
          producer_thread
        rescue Exception => e
          logger.error("#{e.class.name}: #{e.message}")
          logger.backtrace(e)
          raise e
        end
      end
    end

    def stop
      @mutex.synchronize do
        @done = true

        if alive?
          if block_given? then yield else sleep ModelSync::Timeout end
          @thread.raise Interrupt if alive?
        end

        close_connection

        ensure
          @thread = nil
          @done = false
      end
    end

    def alive?
      !@thread.nil? && @thread.alive?
    end

    def name
      NAME
    end

    private
      def logger
        ModelSync.logger
      end

      def multi_logger
        logger.multi_logger
      end

      def done?
        @done
      end

      def sanitize_pg_message(message)
        message.sub(/\R+\s*/, '. ').gsub(/\R+\s*/, ' ').gsub(/\s*$/, '')
      end

      def close_connection
        ( @connection.close rescue StandardError ) if !@connection.nil?
        ( @socket.close rescue StandardError ) if !@socket.nil?

        @connection = nil
        @socket = nil
     end

      def setup_connection
        close_connection

        @connection = ActiveRecord::Base.connection_pool.checkout.tap do |c|
          ActiveRecord::Base.connection_pool.remove(c)
        end

        @connection = @connection.raw_connection

        if !@connection.is_a?(PG::Connection)
          raise(ModelSync::UnsupportedDatabaseError, 'Only PostgreSQL database backend is supported')
        end

        begin
          io = @connection.socket_io

          @socket = Socket.for_fd(io.to_i)
          @socket.autoclose = true
        rescue StandardError
          logger.warn('Unable to create Ruby socket for database connection')
        end

        if !@socket.nil?
          begin
            @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, 1)

            if @socket.local_address.ip?
              logger.info('Tuning database socket TCP keepalive settings')

              @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_KEEPCNT, TCP_KEEPCNT)
              @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_KEEPINTVL, TCP_KEEPINTVL)
              @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_KEEPIDLE, TCP_KEEPIDLE)
            end
          rescue StandardError => e
            logger.warn('Exception trying to tune database socket keepalive settings')
            logger.backtrace(e, :warn)
          end
        end
      end

      def producer_thread
        logger.info("Producer thread started")
        logger.info("Trying to acquire producer lock with resource name " +
          ModelSync::PRODUCER_LOCK)

        loop do
          raise Interrupt if done?

          @lock = Pompa::RedisConnection.lock(ModelSync::PRODUCER_LOCK,
            ModelSync::TIMEOUT)
          raise Interrupt if done?

          break if !@lock.nil?

          rescue Redlock::LockError
        end

        logger.info("Producer lock acquired")

        @connection.async_exec("LISTEN #{ModelSync::CHANNEL}")
        logger.info{"Listening on #{ModelSync::CHANNEL} channel"}

        message_queue = Redis::Queue.new(ModelSync::QUEUE,
          ModelSync::PROCESS_QUEUE, :redis => Pompa::RedisConnection.get,
          :timeout => ModelSync::TIMEOUT)

        logger.info("Bound to #{ModelSync::QUEUE} with #{ModelSync::TIMEOUT}s timeout")

        loop do
          break if done?

          @lock = Pompa::RedisConnection.lock(ModelSync::PRODUCER_LOCK,
            ModelSync::TIMEOUT, :lock_info => @lock)
          break if done?

          if @lock.nil?
            logger.error("Unable to extend producer lock")
            break
          end

          channel_processed = @connection.wait_for_notify(
            ModelSync::TIMEOUT) do |channel, pid, payload|
            next if payload.blank?

            begin
              logger.debug{"Got \"#{payload}\" from #{ModelSync::CHANNEL} channel"}

              operation, model_name, instance_id = payload.split(' ')
              instance_id = instance_id.to_i

              next if !ModelSync::OPERATIONS.include?(operation)
              next if instance_id == 0

              hash = { operation: operation, model_name: model_name,
                instance_id: instance_id }

              multi_logger.debug{["Parsed channel payload into ", hash]}

              message_queue.push(hash.to_json)
            rescue StandardError => e
              logger.error("#{e.class.name}: #{e.message}")
              logger.backtrace(e, :error)
            end
          end

          break if done?

          if channel_processed.blank?
            @connection.query(KEEPALIVE_QUERY)
            message_queue.refill
          end
        end
      rescue Interrupt
      rescue Redis::CannotConnectError => e
        logger.error{"Error #{e.class}: #{e.message}"}
        logger.backtrace(e)
      rescue PG::ConnectionBad => e
        logger.error{"Error #{e.class}: #{sanitize_pg_message(e.message)}"}
        logger.backtrace(e)
      rescue PG::Error => e
        logger.error{"Error #{e.class}: #{sanitize_pg_message(e.message)}"}
        logger.backtrace(e)
      ensure
        Pompa::RedisConnection.unlock(ModelSync::PRODUCER_LOCK,
          :lock_info => @lock) if !@lock.nil?

        logger.info("Producer lock released")

        if !@connection.nil?
          begin @connection.async_exec('UNLISTEN *') rescue StandardError end
          logger.info("Stopped listening on #{ModelSync::CHANNEL} channel")
        end

        logger.info("Producer thread stopped")
      end
  end
end
