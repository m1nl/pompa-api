=begin LICENSE.txt

Copyright (c) 2013 Francesco Laurita

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=end

class Redis
  class Queue
    VERSION = '0.0.4+mnl1'.freeze

    def self.version
      "redis-queue version #{VERSION}"
    end

    def initialize(queue_name, process_queue_name, options = {})
      raise ArgumentError, 'First argument must be a non empty string' if !queue_name.is_a?(String) || queue_name.empty?
      raise ArgumentError, 'Second argument must be a non empty string' if !process_queue_name.is_a?(String) || process_queue_name.empty?
      raise ArgumentError, 'Queue and Process queue have the same name' if process_queue_name == queue_name

      @redis = options[:redis]
      @queue_name = queue_name
      @process_queue_name = process_queue_name
      @timeout = options[:timeout] || 0
    end

    def length
      @redis.llen(@queue_name)
    end

    def clear(clear_process_queue = false)
      @redis.del(@queue_name)
      @redis.del(@process_queue_name) if clear_process_queue
    end

    def empty?
      !(length > 0)
    end

    def push(obj)
      @redis.lpush(@queue_name, obj)
    end

    def pop(non_block = false, timeout = nil)
      timeout = @timeout if timeout.nil?

      if non_block
        return @redis.rpoplpush(@queue_name, @process_queue_name)
      else
        return @redis.brpoplpush(@queue_name, @process_queue_name, :timeout => timeout)
      end
    end

    def commit
      @redis.ltrim(@process_queue_name, 1, -1)
    end

    def process(non_block = false, timeout = nil)
      loop do
        message = pop(non_block, timeout)
        ret = yield message if block_given?
        commit if ret

        break if message.nil? || (non_block && empty?)
      end
    end

    def refill
      while message = @redis.lpop(@process_queue_name)
        @redis.rpush(@queue_name, message)
      end
      true
    end

    alias :size :length
    alias :dec :pop
    alias :shift :pop
    alias :enc :push
    alias :<< :push
  end
end
