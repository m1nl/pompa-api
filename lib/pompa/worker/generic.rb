require 'pompa/worker/const'

module Pompa
  module Worker
    module Generic
      include Const

      def instance_id
        raise Pompa::Worker::InvalidInstanceException.new(
           'could not determine instance_id')
      end

      def worker_class_name
        return super if defined?(super)
        return self.class.name if self.class.name != CLASS
        return self.name
      end

      def worker_class
        worker_class_name.constantize
      end

      def reply_queue_key_name(opts = {})
        timeout = opts.delete(:timeout) || expiry_timeout
        queue_id = opts.delete(:queue_id)

        queue_id ||= reply_queue_id if queue_id.blank?
        queue_key_name = "#{ANONYMOUS}:#{queue_id}"

        Pompa::RedisConnection.redis(opts) { |r|
          r.expire(queue_key_name, timeout)
        }

        return queue_key_name
      end

      def reply_queue_id(queue_name = nil)
        return Pompa::Utils.uuid if queue_name.blank?

        queue_elements = queue_name.split(':')
        return queue_elements[1] if queue_elements.length == 2 &&
          queue_elements[0] == ANONYMOUS
      end
    end
  end
end
