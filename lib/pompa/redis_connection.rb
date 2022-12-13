require 'redis'
require 'redlock'
require 'connection_pool'
require 'uri'

module Pompa
  class RedisConnection
    DEFAULT_DB = :_default
    CACHE_DB = :cache
    LOCK_DB = :lock
    SIDEKIQ_DB = :sidekiq
    EVENTS_DB = :events
    AUTH_DB = :auth

    CACHE_DB_NAMESPACE = :pompa_cache

    SYMBOLIZE_VALUES_FOR = [:driver, :role].freeze

    class << self
      def pool(opts = {})
        @pool ||= {}

        db = opts.delete(:db) || DEFAULT_DB
        db = db.to_sym

        return @pool[db] if !@pool[db].nil?

        size = opts.delete(:pool_size) || pool_size

        config = config(opts.merge(:db => db)).freeze

        @pool[db] = ConnectionPool.new(size: size) { Redis.new(config) }
      end

      def redis(opts = {})
        raise ArgumentError, 'Method requires a block' unless block_given?

        return pool(opts).with { |r| yield(r) } if !opts[:db].nil?

        if !opts[:redis].nil?
          yield(opts[:redis])
        elsif !opts[:pool].nil?
          opts[:pool].with { |r| yield(r) }
        else
          pool(opts).with { |r| yield(r) }
        end
      end

      def locked(resource_key, timeout, opts = {})
        raise ArgumentError, 'Method requires a block' unless block_given?

        lock_key = opts[:lock_key] || "Lock:#{resource_key}"
        lock_info = opts[:lock_info] || ::Thread.current[lock_key]

        already_locked = !!lock_info

        redis(opts.merge(:db => LOCK_DB)) do |r|
          lock(resource_key, timeout, opts.merge(:redis => r))

          begin
            return yield
          ensure
            unlock(resource_key, opts.merge(:redis => r)) if !already_locked
          end
        end
      end

      def lock(resource_key, timeout, opts = {})
        lock_key = opts[:lock_key] || "Lock:#{resource_key}"
        lock_info = opts[:lock_info] || ::Thread.current[lock_key]

        already_locked = !!lock_info

        redis(opts.merge(:db => LOCK_DB)) do |r|
          if already_locked
            lock_info = lock_manager.lock(lock_key, timeout.in_milliseconds,
              extend: lock_info)
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
        Redis.new(config(opts))
      end

      def config(opts = {})
        @config ||= {}

        db = opts.delete(:db) || DEFAULT_DB
        db = db.to_sym

        return @config[db] if !@config[db].nil?

        config = {}

        Rails.configuration.pompa.redis.to_h.symbolize_keys.each do |k, v|
          if v.is_a?(Hash)
            db_config = v.symbolize_keys
            config[k] = db_config[db] || db_config[DEFAULT_DB]
          else
            config[k] = v
          end

          config.except!(k) if config[k].nil?
        end

        config.merge!(config.extract!(*SYMBOLIZE_VALUES_FOR)
          .transform_values!(&:to_sym))

        url = config.delete(:url)
        uri = URI(url)

        if uri.scheme == "unix"
          config[:path] = uri.path
        else
          config[:url] = uri.to_s
        end

        config.delete(:pool_size)

        @config[db] = config.freeze
      end

      def pool_size=(value)
        if !value.nil?
          @pool_size = value
          @pool = nil
        end

        pool_size
      end

      private
        def pool_size
          @pool_size ||= Rails.configuration.pompa.redis.pool_size
        end

        def lock_manager(opts = {})
          @lock_manager ||= Redlock::Client.new(
            [Redis.new(config(opts))],
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
