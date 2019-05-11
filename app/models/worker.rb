require 'oj'

class Worker
  extend ActiveModel::Naming

  extend Pompa::Worker::State
  extend Pompa::Worker::Control

  include ActiveModel::Model
  include ActiveModel::Serialization

  include Pompa::Worker::State
  include Pompa::Worker::Control

  attr_accessor :id, :instance_id, :worker_class_name, :message_queue, :started_at
  validates :id, :instance_id, :worker_class_name, :message_queue, presence: true

  alias_method :jid, :id

  def initialize(attributes = {})
    @id = attributes[:id]
    @instance_id = attributes[:instance_id]
    @worker_class_name = attributes[:worker_class_name]
    @message_queue = attributes[:message_queue]
    @started_at = attributes[:started_at]
  end

  def save(opts = {})
    return if !valid?

    timeout = opts.delete(:timeout) || expiry_timeout * 2

    Pompa::RedisConnection.redis(opts) do |r|
      r.multi do |m|
        m.setex(worker_key_name, timeout, to_json)
        m.sadd(worker_set_name, worker_key_name)
      end
    end

    return self
  end

  def persisted?(opts = {})
    Pompa::RedisConnection.redis(opts) do |r|
      r.exists(worker_key_name) &&
        r.sismember(worker_set_name, worker_key_name)
    end
  end

  def destroy(opts = {})
    return false if !persisted?

    Pompa::RedisConnection.redis(opts) { |r| r.srem(worker_set_name,
      worker_key_name) }

    return true
  end

  def mark(opts = {})
    return false if !persisted?

    timeout = opts.delete(:timeout) || expiry_timeout

    Pompa::RedisConnection.redis(opts) { |r| r.expire(worker_key_name,
      timeout) }

    return true
  end

  def worker_class_name
    @worker_class_name
  end

  def model_class_name
    worker_class.model_class_name
  end

  def model_class
    worker_class.model_class
  end

  def model
    model_class.find_by_id(instance_id)
  end

  class << self
    def all(opts = {})
      workers = []

      Pompa::RedisConnection.redis(opts) do |r|
        r.smembers(worker_set_name).each do |w|
          begin
            json = r.get(w)
            next if json.blank?

            hash = Oj.load(json, symbol_keys: true)
            worker = Worker.new(hash)
            next if !worker.valid?

            workers.push(worker)
          rescue Oj::ParseError
          end
        end
      end

      workers.define_singleton_method(:name) { 'Worker' }
      return workers
    end

    def find_by_id(id, opts = {})
      worker = nil

      Pompa::RedisConnection.redis(opts) do |r|
        begin
          json = r.get(worker_key_name(id))
          return if json.blank?

          hash = Oj.load(json, symbol_keys: true)
          worker = Worker.new(hash)
          return if !worker.valid?
        rescue Oj::ParseError
        end
      end

      return worker
    end

    def each(opts = {})
      Pompa::RedisConnection.redis(opts) do |r|
        r.sscan_each(worker_set_name) do |i|
          begin
            json = r.get(i)
            next if json.blank?

            hash = Oj.load(json, symbol_keys: true)
            worker = Worker.new(hash)
            next if !worker.valid?

            yield worker
          rescue Oj::ParseError
          end
        end
      end
    end

    def create(args = {})
      self.new(args).save(args)
    end

    def worker_key_name(id)
      "#{self.name}:#{id}"
    end

    def worker_set_name
      "#{self.name}:Set"
    end
  end

  private
    def worker_key_name
      self.class.worker_key_name(id)
    end

    def worker_set_name
      self.class.worker_set_name
    end
end
