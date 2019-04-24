require 'pompa/redis_connection'
require 'pompa/worker/generic'

module Pompa
  module Worker
    module State
      include Generic

      def last_active(opts = {})
        instance_id = opts.delete(:instance_id) || self.instance_id
        name = opts.delete(:name) || self.worker_class_name

        opts[:pool] ||= redis if defined?(redis)

        last_active_string = Pompa::RedisConnection.redis(opts) { |r|
          r.get(last_active_key_name(instance_id, name)) }

        return Time.at(0) if last_active_string.blank?
        return Time.iso8601(last_active_string)
      end

      def worker_state(opts = {})
        instance_id = opts.delete(:instance_id) || self.instance_id
        name = opts.delete(:name) || self.worker_class_name

        opts[:pool] ||= redis if defined?(redis)

        Pompa::RedisConnection.redis(opts) { |r|
          r.get(worker_state_key_name(instance_id, name)) }
      end

      def last_active_key_name(instance_id = self.instance_id,
        name = worker_class_name)
        "#{name}:#{instance_id}:last_active"
      end

      def worker_state_key_name(instance_id = self.instance_id,
        name = worker_class_name)
        "#{name}:#{instance_id}:worker_state"
      end
    end
  end
end
