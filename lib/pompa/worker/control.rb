require 'json'
require 'pompa/redis_connection'
require 'pompa/worker/generic'

module Pompa
  module Worker
    module Control
      include Generic

      def resync(opts = {})
        timeout = opts.delete(:timeout) || expiry_timeout
        instance_id = opts.delete(:instance_id) || self.instance_id
        name = opts.delete(:name) || self.worker_class_name

        opts[:pool] ||= redis if defined?(redis)

        Pompa::RedisConnection.redis(opts) do |r|
          r.pipelined do |p|
            Array(instance_id).each do |i|
              queue_name = resync_key_name(i, name)
              p.setex(queue_name, timeout, 1)
            end
          end
        end

        return ping(opts.merge(:name => name, :instance_id => instance_id,
          :timeout => timeout, :head => true))
      end

      def cancel(opts = {})
        timeout = opts.delete(:timeout) || expiry_timeout
        instance_id = opts.delete(:instance_id) || self.instance_id
        name = opts.delete(:name) || self.worker_class_name
        discard = !!opts.delete(:discard)

        opts[:pool] ||= redis if defined?(redis)

        Pompa::RedisConnection.redis(opts) do |r|
          r.pipelined do |p|
            Array(instance_id).each do |i|
              queue_name = cancel_key_name(i, name)
              p.setex(queue_name, timeout, discard ? CANCEL_DISCARD : CANCEL_NORMAL)
            end
          end
        end

        return ping(opts.merge(:name => name, :instance_id => instance_id,
          :timeout => timeout, :head => true))
      end

      def discard(opts = {})
        timeout = opts.delete(:timeout) || expiry_timeout
        instance_id = opts.delete(:instance_id) || self.instance_id
        name = opts.delete(:name) || self.worker_class_name

        opts[:pool] ||= redis if defined?(redis)

        Pompa::RedisConnection.redis(opts) do |r|
          r.pipelined do |p|
            Array(instance_id).each do |i|
              p.multi do |m|
                m.del(resync_key_name(i, name))
                m.del(cancel_key_name(i, name))
                m.del(message_queue_key_name(i, name))
                m.del(message_process_queue_key_name(i, name))
                m.del(subscribe_key_name(i, name))
                m.del(last_active_key_name(i, name))
                m.del(worker_state_key_name(i, name))

                worker_class.cleanup(opts.merge(:name => name, :instance_id => i,
                  :timeout => timeout, :redis => m)) if worker_class
                  .respond_to?(:cleanup)
              end
            end
          end
        end

        return true
      end

      def subscribe(queue_name, opts = {})
        instance_id = opts.delete(:instance_id) || self.instance_id
        name = opts.delete(:name) || self.worker_class_name

        opts[:pool] ||= redis if defined?(redis)

        Pompa::RedisConnection.redis(opts) do |r|
          r.pipelined do |p|
            Array(instance_id).each do |i|
              r.sadd(subscribe_key_name(i, name),
                queue_name)
            end
          end
        end
      end

      def unsubscribe(queue_name, opts = {})
        instance_id = opts.delete(:instance_id) || self.instance_id
        name = opts.delete(:name) || self.worker_class_name

        opts[:pool] ||= redis if defined?(redis)

        Pompa::RedisConnection.redis(opts) do |r|
          r.pipelined do |p|
            Array(instance_id).each do |i|
              r.srem(subscribe_key_name(i, name),
                queue_name)
            end
          end
        end
      end

      def message(message, opts = {})
        return if !message.is_a?(Hash)

        instance_id = opts.delete(:instance_id) || self.instance_id
        sync = !!opts.delete(:sync)

        opts[:pool] ||= redis if defined?(redis)

        return message_async(message,
          opts.merge(:instance_id => instance_id)) unless sync

        result = []
        Array(instance_id).each do |i|
          result << message_sync(message, opts.merge(:instance_id => i))
        end

        return result.length == 1 ? result.first : result
      end

      def ping(opts = {})
        timeout = opts.delete(:timeout) || expiry_timeout

        return message(PING.deep_dup.merge(
          :expires => timeout.seconds.from_now), opts.merge(
            :timeout => timeout))
      end

      ### Locking

      def with_worker_lock(opts = {})
        raise ArgumentError, 'Method requires a block' unless block_given?

        instance_id = opts.delete(:instance_id) || self.instance_id
        name = opts.delete(:name) || self.worker_class_name

        opts[:pool] ||= redis if defined?(redis)

        Pompa::RedisConnection.locked(worker_lock_key_name(instance_id, name),
          queue_timeout, opts) { |r| yield(r) }
      end

      def worker_lock(opts = {})
        instance_id = opts.delete(:instance_id) || self.instance_id
        name = opts.delete(:name) || self.worker_class_name

        opts[:pool] ||= redis if defined?(redis)

        Pompa::RedisConnection.lock(worker_lock_key_name(instance_id, name),
          queue_timeout, opts)
      end

      def worker_unlock(opts = {})
        instance_id = opts.delete(:instance_id) || self.instance_id
        name = opts.delete(:name) || self.worker_class_name

        opts[:pool] ||= redis if defined?(redis)

        Pompa::RedisConnection.unlock(worker_lock_key_name(instance_id, name),
          opts)
      end

      def worker_locked?(opts = {})
        instance_id = opts.delete(:instance_id) || self.instance_id
        name = opts.delete(:name) || self.worker_class_name

        opts[:pool] ||= redis if defined?(redis)

        Pompa::RedisConnection.lock_valid?(worker_lock_key_name(instance_id, name),
          opts)
      end

      ###

      def worker_lock_key_name(instance_id = self.instance_id,
        name = worker_class_name)
        "#{name}:#{instance_id}:lock"
      end

      def resync_key_name(instance_id = self.instance_id,
        name = worker_class_name)
        "#{name}:#{instance_id}:resync"
      end

      def cancel_key_name(instance_id = self.instance_id,
        name = worker_class_name)
        "#{name}:#{instance_id}:cancel"
      end

      def message_queue_key_name(instance_id = self.instance_id,
        name = worker_class_name)
        "#{name}:#{instance_id}:message_queue"
      end

      def message_process_queue_key_name(instance_id = self.instance_id,
        name = worker_class_name)
        "#{name}:#{instance_id}:message_process_queue"
      end

      def subscribe_key_name(instance_id = self.instance_id,
        name = worker_class_name)
        "#{name}:#{instance_id}:subscribers"
      end

      protected
        def message_sync(message, opts = {})
          timeout = opts.delete(:timeout) || expiry_timeout
          instance_id = opts.delete(:instance_id) || self.instance_id
          name = opts.delete(:name) || self.worker_class_name
          head = !!opts.delete(:head)

          message[:request_id] ||= opts[:request_id] || Pompa::Utils.uuid
          message[:reply_to] ||= reply_queue_key_name
          message[:expires] ||= (timeout * 2).seconds.from_now

          queue_key_name = message_queue_key_name(instance_id, name)

          Pompa::RedisConnection.redis(opts) do |r|
            if head
              r.lpush(queue_key_name, message.to_json)
            else
              r.rpush(queue_key_name, message.to_json)
            end

            ## unlock if locked to prevent deadlock
            locked = worker_locked?(opts.merge(:redis => r,
              :instance_id => instance_id, :name => name))
            worker_unlock(opts.merge(:redis => r,
              :instance_id => instance_id, :name => name)) if locked

            response = r.blpop(message[:reply_to], :timeout => timeout)

            worker_lock(opts.merge(:redis => r,
              :instance_id => instance_id, :name => name)) if locked

            r.expire(message[:reply_to], timeout)
            return TIMEOUT_RESPONSE if response.nil?

            json = response[1]
            begin
              return JSON.parse(json, symbolize_names: true)
            rescue JSON::ParserError
              return INVALID_RESPONSE
            end
          end

          return TIMEOUT_RESPONSE
        end

        def message_async(message, opts = {})
          timeout = opts.delete(:timeout) || expiry_timeout
          instance_id = opts.delete(:instance_id) || self.instance_id
          name = opts.delete(:name) || self.worker_class_name
          head = !!opts.delete(:head)

          message[:reply_to] ||= opts[:reply_to]

          Pompa::RedisConnection.redis(opts) do |r|
            if message[:reply_to].nil?
              message[:reply_to] = reply_queue_key_name
              r.expire(message[:reply_to], timeout)
            end

            r.pipelined do |p|
              Array(instance_id).each do |i|
                queue_key_name = message_queue_key_name(i, name)
                message[:request_id] ||= opts[:request_id] || Pompa::Utils.uuid

                if head
                  p.lpush(queue_key_name, message.to_json)
                else
                  p.rpush(queue_key_name, message.to_json)
                end
              end
            end
          end

          return message[:reply_to]
        end
    end
  end
end
