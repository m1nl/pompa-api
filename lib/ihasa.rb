=begin LICENSE.txt

Copyright (c) 2012-14 Bozhidar Batsov

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

require 'redis'
require 'ihasa/version'

# Ihasa module. Root of the Ihasa::Bucket class
module Ihasa
  NOK = 0
  OK = 1
  OPTIONS = %i(rate burst last allowance).freeze

  require 'ihasa/bucket'

  module_function

  def default_redis
    @redis ||= if ENV['REDIS_URL']
                 Redis.new url: ENV['REDIS_URL']
               else
                 Redis.new
               end
  end

  DEFAULT_PREFIX = 'IHAB'.freeze
  def bucket(rate: 5, burst: 10, prefix: DEFAULT_PREFIX, redis: default_redis)
    Bucket.create(rate, burst, prefix, redis)
  end
end
