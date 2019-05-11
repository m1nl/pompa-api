require 'ihasa/lua'

module Ihasa
  # Bucket class. That bucket fills up to burst, by rate per
  # second. Each accept? or accept?! call decrement it from 1.
  class Bucket
    class << self
      def create(*args)
        new(*args).tap(&:save)
      end
    end

    attr_reader :redis, :keys, :rate, :burst, :prefix
    def initialize(rate, burst, prefix, redis)
      require 'ihasa/bucket/implementation'
      @implementation = Implementation.instance

      @prefix = prefix
      @keys = Ihasa::OPTIONS.map { |opt| "#{prefix}:#{opt.upcase}" }
      @redis = redis
      @rate = Float rate
      @burst = Float burst
    end

    SETUP_ADVICE = 'Ensure that the method ' \
      'Ihasa::Bucket#save was called.'.freeze
    SETUP_ERROR = ('Redis raised an error: %{msg}. ' + SETUP_ADVICE).freeze

    class RedisNamespaceSetupError < RuntimeError; end

    def accept?
      result = @implementation.accept?(self) == OK
      return yield if result && block_given?
      result
    rescue Redis::CommandError => e
      raise RedisNamespaceSetupError, SETUP_ERROR % { msg: e.message }
    end

    class EmptyBucket < RuntimeError; end

    def accept!
      result = (block_given? ? accept?(&Proc.new) : accept?)
      raise EmptyBucket, "Bucket #{prefix} throttle limit" unless result
      result
    end

    def save
      @implementation.save(self)
    end

    def delete
      redis.del(keys)
    end
  end
end
