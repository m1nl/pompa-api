require 'pompa/worker/const'

module Pompa
  module Worker
    module Generic
      include Const

      def worker_class_name
        return super if defined?(super)
        return self.class.name if self.class.name != CLASS
        return self.name
      end

      def worker_class
        worker_class_name.constantize
      end

      def reply_queue_key_name(queue_id = nil)
        queue_id ||= reply_queue_id
        "#{ANONYMOUS}:#{queue_id}"
      end

      def reply_queue_id(queue_name = nil)
        return Pompa::Utils.uuid if queue_name.nil?

        queue_elements = queue_name.split(':')
        return queue_elements[1] if queue_elements.length == 2 &&
          queue_elements[0] == ANONYMOUS
      end
    end
  end
end
