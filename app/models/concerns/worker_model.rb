require 'pompa'
require 'active_support/concern'

module WorkerModel
  extend ActiveSupport::Concern

  include Pompa::Worker::State
  include Pompa::Worker::Control

  included do
    after_commit :worker_update, on: :update

    scope :active, -> { where.not(jid: nil) }
    scope :inactive, -> { where(jid: nil) }

    extend Pompa::Worker::State
    extend Pompa::Worker::Control

    extend FinalClassMethods
  end

  ### Class method invocations

  [:claim_jid, :release_jid].each { |m| define_method m do |jid, opts = {}|
      self.class.public_send(m, instance_id, jid, opts)
    end }

  [:worker_class_name, :worker_auto_start?,
   :worker_auto_spawn?].each { |m| define_method m do
      self.class.public_send(m)
    end }

  [:start_worker, :stop_worker, :worker_active?, :worker_cancelled?,
    :worker_started?].each { |m| define_method m do |opts = {}|
      self.class.public_send(m, instance_id, opts)
    end }

  [:resync, :cancel, :ping].each { |m| define_method m do |opts = {}|
      self.class.public_send(m, opts.merge(:instance_id => instance_id))
  end }

  [:message].each { |m| define_method m do |message, opts = {}|
      self.class.public_send(m, message, opts.merge(:instance_id => instance_id))
  end }

  ###

  def instance_id
    self.id
  end

  def worker_finished?
    !self.class.worker_finished.nil? &&
      instance_exec(&self.class.worker_finished)
  end

  def trigger_resync?
    @trigger_resync.nil? || @trigger_resync
  end

  def trigger_resync=(value)
    @trigger_resync = !!value
  end

  private
    def worker_update
      Pompa::RedisConnection.redis { |r|
        r.del(worker_started_key_name) } if saved_change_to_jid?
      resync if trigger_resync?
    end

    def worker_started_key_name
      self.class.worker_started_key_name(instance_id)
    end

    ###

    module FinalClassMethods
      def worker_class_name
        "#{self.name}#{WorkerJob::SUFFIX}"
      end

      def worker_auto(opts = {})
        @worker_auto_start = !!opts[:start]
        @worker_auto_spawn = !!opts[:spawn]
      end

      def worker_finished(condition = nil)
        @worker_finished ||= condition
      end

      def worker_auto_start?
        @worker_auto_start ||= false
      end

      def worker_auto_spawn?
        @worker_auto_spawn ||= false
      end

      def claim_jid(instance_id, jid, opts = {})
        return false if instance_id.nil? || jid.nil?

        return true if (self
          .where(id: instance_id)
          .where(jid: [nil, jid])
          .update_all(jid: jid) == 1)

        current_jid = self
          .where(id: instance_id)
          .pluck(:jid)
          .first

        current_worker = Worker.find_by_id(current_jid)

        return false if !current_worker.nil? && current_worker.valid? &&
          ![Pompa::Worker::FAILED, Pompa::Worker::CANCELLED].include?(
            current_worker.worker_state)

        return false unless (self
          .where(id: instance_id)
          .where(jid: current_jid)
          .update_all(jid: nil) == 1)

        claim_jid(instance_id, jid, opts = {})
      end

      def release_jid(instance_id, jid, opts = {})
        return false if instance_id.nil? || jid.nil?

        Pompa::RedisConnection.redis(opts) { |r|
          r.del(worker_started_key_name(instance_id)) }

        self
          .where(id: instance_id)
          .where(jid: [nil, jid])
          .update_all(jid: nil) == 1
      end

      def start_worker(instance_id, opts = {})
        with_worker_lock(opts.merge(:instance_id => instance_id)) do
          return if !opts.delete(:force) && worker_active?(instance_id, opts)

          worker_class.perform_later(opts.merge(:instance_id => instance_id)
            .except(*Pompa::Worker::REDIS_OPTS))
          worker_started!(instance_id, opts)
        end
      end

      def stop_worker(instance_id, opts = {})
        discard = !!opts.delete(:discard)

        with_worker_lock(opts.merge(:instance_id => instance_id)) do
          # force DB query to check if worker is running
          Pompa::RedisConnection.redis { |r|
            r.del(worker_started_key_name(instance_id)) }

          if worker_active?(instance_id, opts)
            cancel(opts.merge(:instance_id => instance_id, :discard => discard))
          else
            discard(opts.merge(:instance_id => instance_id)) if discard
          end
        end
      end

      def worker_active?(instance_id, opts = {})
        with_worker_lock(opts.merge(:instance_id => instance_id)) do
          return true if worker_started?(instance_id, opts)

          current_jid = self
            .where(id: instance_id)
            .pluck(:jid)
            .first

          current_worker = Worker.find_by_id(current_jid)

          !current_worker.nil? && current_worker.valid? &&
            ![Pompa::Worker::FAILED, Pompa::Worker::CANCELLED].include?(
            current_worker.worker_state) && worker_started!(instance_id, opts)
        end
      end

      def worker_started?(instance_id, opts = {})
        with_worker_lock(opts.merge(:instance_id => instance_id)) do
          Pompa::RedisConnection.redis(opts) { |r|
            r.exists(worker_started_key_name(instance_id)) }
        end
      end

      def worker_cancelled?(instance_id, opts = {})
        with_worker_lock(opts.merge(:instance_id => instance_id)) do
          Pompa::RedisConnection.redis(opts) { |r|
            r.exists(cancel_key_name(instance_id)) }
        end
      end

      def worker_finished?(instance_id)
        find_by_id(instance_id).worker_finished?
      end

      ### Overrides

      def resync(opts = {})
        instance_id = opts.delete(:instance_id)

        with_worker_lock(opts.merge(:instance_id => instance_id)) do
          return if !opts.delete(:force) && !worker_active?(instance_id, opts)

          super(opts.merge(:instance_id => instance_id))
        end
      end

      def cancel(opts = {})
        instance_id = opts.delete(:instance_id)

        with_worker_lock(opts.merge(:instance_id => instance_id)) do
          return if !opts.delete(:force) && !worker_active?(instance_id, opts)

          super(opts.merge(:instance_id => instance_id))
        end
      end

      def message(message, opts = {})
        instance_id = opts.delete(:instance_id)

        with_worker_lock(opts.merge(:instance_id => instance_id)) do
          start_worker(instance_id,
            opts.slice(*Pompa::Worker::REDIS_OPTS)) if worker_auto_spawn?

          super(message, opts.merge(:instance_id => instance_id))
        end
      end

      def ping(opts = {})
        instance_id = opts.delete(:instance_id)

        with_worker_lock(opts.merge(:instance_id => instance_id)) do
          start_worker(instance_id,
            opts.slice(*Pompa::Worker::REDIS_OPTS)) if worker_auto_spawn?

          super(opts.merge(:instance_id => instance_id))
        end
      end

      ###

      def worker_started_key_name(instance_id)
        "#{worker_class.name}:#{instance_id}:started"
      end

      private
        def worker_started!(instance_id, opts = {})
          Pompa::RedisConnection.redis(opts) { |r| r.setex(
            worker_started_key_name(instance_id), queue_timeout, 1) }

          return true
        end
    end
end
