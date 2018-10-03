require "redis"
require "redis/store"
require "redlock"
require "connection_pool"

module Pompa
  class RedisConnection
    class << self
      SYMBOLIZE_VALUES_FOR = [:driver, :role].freeze

      def pool(opts = {})
        opts[:size] ||= pool_size

        if !!opts[:store]
          ConnectionPool.new(size: opts[:size], &redis_store_connection)
        else
          ConnectionPool.new(size: opts[:size], &redis_connection)
        end
      end

      def common_pool(opts = {})
        if !!opts[:store]
          redis_store_common_pool
        else
          redis_common_pool
        end
      end

      def redis(opts = {})
        raise ArgumentError, 'Method requires a block' unless block_given?

        if !opts[:redis].nil?
          yield(opts[:redis])
        elsif !opts[:pool].nil?
          opts[:pool].with { |r| yield(r) }
        else
          redis_common_pool.with { |r| yield(r) }
        end
      end

      def locked(resource_key, timeout, opts = {})
        raise ArgumentError, 'Method requires a block' unless block_given?

        lock_key = opts[:lock_key] || "Lock:#{resource_key}"
        lock_info = opts[:lock_info] || ::Thread.current[lock_key]

        already_locked = !!lock_info

        redis(opts) do |r|
          lock(resource_key, timeout, opts.merge(:redis => r))

          begin
            return yield(r)
          ensure
            unlock(resource_key, opts.merge(:redis => r)) if !already_locked
          end
        end
      end

      def lock(resource_key, timeout, opts = {})
        lock_key = opts[:lock_key] || "Lock:#{resource_key}"
        lock_info = opts[:lock_info] || ::Thread.current[lock_key]

        already_locked = !!lock_info

        redis(opts) do |r|
          if already_locked
            lock_info = lock_manager.lock(lock_key, timeout.in_milliseconds,
              extend: lock_info, extend_life: !!lock_info)
          end

          if !lock_info
            lock_info = lock_manager.lock(lock_key, timeout.in_milliseconds)
          end

          if lock_info
            ::Thread.current[lock_key] = lock_info
          else
            ::Thread.current[lock_key] = nil
            raise Redlock::LockError, 'failed to acquire lock'
          end
        end
      end

      def unlock(resource_key, opts = {})
        lock_key = opts[:lock_key] || "Lock:#{resource_key}"
        lock_info = opts[:lock_info] || ::Thread.current[lock_key]

        already_locked = !!lock_info
        return false if !already_locked

        ::Thread.current[lock_key] = nil
        lock_manager.unlock(lock_info)
        return true
      end

      def lock_valid?(resource_key, opts = {})
        lock_key = opts[:lock_key] || "Lock:#{resource_key}"
        lock_info = opts[:lock_info] || ::Thread.current[lock_key]

        already_locked = !!lock_info
        return false if !already_locked

        lock_manager.valid?(lock_info)
      end

      def get(opts = {})
        if !!opts[:store]
          redis_store_connection.call
        else
          redis_connection.call
        end
      end

      def config
        return @config if !@config.nil?

        @config = Rails.configuration.pompa.redis.to_h.deep_dup
        @config = @config.symbolize_keys!

        symbols = @config.extract!(*SYMBOLIZE_VALUES_FOR)
          .transform_values!(&:to_sym)

        @config.merge!(symbols)
      end

      private
        def redis_connection
          @redis_connection ||= proc { Redis.new(config) }
        end

        def redis_store_connection
          @redis_store_connection ||= proc { Redis::Store.new(config) }
        end

        def redis_common_pool
          @redis_common_pool ||= pool
        end

        def redis_store_common_pool
          @redis_store_common_pool ||= pool(:store => true)
        end

        def pool_size
          @pool_size ||= Rails.configuration.pompa.redis.pool_size
        end

        def lock_manager
          @lock_manager ||= Redlock::Client.new([redis_connection.call],
            :retry_count => retry_count,
            :retry_delay => retry_delay.in_milliseconds)
        end

        def retry_count
          @retry_count ||= Rails.configuration.pompa
            .lock.retry_count
        end

        def retry_delay
          @retry_delay ||= Rails.configuration.pompa
            .lock.retry_delay.seconds
        end
    end
  end
end
