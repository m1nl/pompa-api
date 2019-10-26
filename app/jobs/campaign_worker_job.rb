class CampaignWorkerJob < WorkerJob
  queue_as :campaigns

  class << self
    def cleanup(opts)
      Pompa::RedisConnection.redis(opts) do |r|
        r.del(queued_victims_set_name(opts[:instance_id]))
        r.del(error_count_key_name(opts[:instance_id]))
      end
    end

    def queued_victims_set_name(instance_id)
      "#{name}:#{instance_id}:queued_victims"
    end

    def error_count_key_name(instance_id)
      "#{name}:#{instance_id}:error_count"
    end
  end

  protected
    def finished?
      super || model.worker_finished?
    end

    def respawn?
      (Time.current - started_at) > respawn_interval
    end

    def tick
      case model.state
        when Campaign::CREATED
          return start if !model.start_date.nil? &&
            model.start_date <= Time.current
        when Campaign::STARTED
          return if !model.start_date.nil? &&
            model.start_date > Time.current
          return finish if !model.finish_date.nil? &&
            model.finish_date <= Time.current

          mark
          try_sync

          redis.with do |r|
            return if queued_victims_length != 0

            model.scenarios.each do |s|

              Victim.uncached do
                Victim
                  .pending
                  .where(scenario_id: s.id)
                  .order(:id)
                  .take(victim_batch_size)
                  .each do |v|

                  v.with_worker_lock(:redis => r) do
                    logger.debug("Triggering email and subscribing victim ##{v.id}")
                    v.subscribe(message_queue_key_name, :redis => r)
                    v.send_email(:redis => r)
                  end

                  logger.debug("Spawned and subscribed victim ##{v.id}")
                  add_queued_victim(v.id)
                end
              end
            end
          end
        when Campaign::PAUSED
          return finish if !model.finish_date.nil? &&
            model.finish_date <= Time.current

          mark
          try_sync
        when Campaign::FINISHED
      end
    end

    def process(message)
      return process_result(message) if message[:result].is_a?(Hash)
      return process_action(message) if !message[:action].blank?
      return result(INVALID, 'Invalid message')
    end

  private
    def process_result(message)
      status = message.dig :result, :status
      value = message.dig :result, :value
      origin_id = message.dig :origin, :instance_id
      origin_name = message.dig :origin, :name

      return result(INVALID,
        'Invalid result') if status.nil? || origin_id.nil? || origin_name.nil?


      return result(INVALID,
        'Unable to process result') if origin_name != VictimWorkerJob.name ||
        !is_victim_queued(origin_id)

      return result(SUCCESS) if status != WORKER_STATE_CHANGE # ignore

      case value
        when FINISHED, CANCELLED
          delete_queued_victim(origin_id)

          Victim.uncached do
            victim = Victim.find_by_id(origin_id)

            if !victim.nil?
              victim.unsubscribe(message_queue_key_name, :pool => redis)
              increase_error_count if victim.state == Victim::ERROR

              return pause if error_count >= error_threshold
              return result(SUCCESS, "Victim ##{victim.id} cleared from the queue")
            else
              return result(INVALID, "Victim ##{origin_id} does not exist")
            end
          end
        else
          return result(SUCCESS) # ignore
      end
    end

    def process_action(message)
      action = message.dig :action
      return result(INVALID, 'Invalid action') if action.blank?

      case action
        when Campaign::START
          return start
        when Campaign::PAUSE
          return pause
        when Campaign::FINISH
          return finish
      end

      return result(INVALID, 'Unable to process action')
    end

    def start
      model.with_lock do
        return result(INVALID, 'Campaign is scheduled') if !model.start_date.nil? &&
          model.start_date > Time.current
        return result(INVALID, 'Invalid state') if model.state != Campaign::CREATED &&
          model.state != Campaign::PAUSED

        model.state = Campaign::STARTED
        model.started_date ||= Time.current
        model.save!

        clear_queued_victims
        reset_error_count
      end

      return result(Campaign::STATE_CHANGE, Campaign::STARTED)
     end

    def pause
      model.with_lock do
        return result(INVALID, 'Invalid state') if model.state != Campaign::STARTED

        model.state = Campaign::PAUSED
        model.save!
      end

      return result(Campaign::STATE_CHANGE, Campaign::PAUSED)
    end

    def finish
      model.with_lock do
        return result(INVALID, 'Invalid state') if model.state != Campaign::STARTED &&
          model.state != Campaign::PAUSED

        model.state = Campaign::FINISHED
        model.finished_date = Time.current
        model.save!
      end

      return result(Campaign::STATE_CHANGE, Campaign::FINISHED)
    end

    def try_sync
      return false unless sync_required?

      logger.debug('Attempting to synchronize events')
      model.synchronize_events(:db => public_redis_db)

      if queued_victims_length < victim_batch_size
        logger.debug('Attempting to synchronize victims')

        model.scenarios.each do |s|
          Victim.uncached do
            Victim.queued.inactive.where(scenario_id: s.id)
              .take(victim_batch_size - queued_victims_length)
              .each do |v|
              next if v.worker_started?

              v.with_worker_lock(:redis => r) do
                logger.debug("Starting worker and subscribing victim ##{v.id}")
                v.subscribe(message_queue_key_name, :pool => redis)
                v.start_worker(:pool => redis)
              end

              logger.debug("Spawned and subscribed victim ##{v.id}")
              add_queued_victim(v.id)
            end
          end
        end
      end

      if queued_victims_length != 0
        existing_ids = Victim.where(id: queued_victims).pluck(:id)
        (queued_victims - existing_ids).each do |v|
          delete_queued_victim(v)
          logger.debug{"Unsubscribed for events from non-existent victim: " +
            "##{v}"}
        end
      end

      if queued_victims_length != 0
        logger.debug{"Currently subscribed for events from victims: " +
          "##{queued_victims.join(', #')}"}
      end

      @last_sync = Time.current
    end

    ###

    def sync_required?
      @last_sync.nil? ||
        (Time.current - @last_sync) > sync_interval
    end

    def clear_queued_victims
      redis.with { |r| r.del(queued_victims_set_name) }
    end

    def add_queued_victim(victim_id)
      redis.with { |r| r.sadd(queued_victims_set_name, victim_id) }
    end

    def delete_queued_victim(victim_id)
      redis.with { |r| r.srem(queued_victims_set_name, victim_id) }
    end

    def queued_victims_length
      redis.with { |r| (r.scard(queued_victims_set_name) || 0).to_i }
    end

    def queued_victims
      redis.with { |r| r.smembers(queued_victims_set_name) }
    end

    def is_victim_queued(victim_id)
      redis.with { |r| r.sismember(queued_victims_set_name, victim_id) }
    end

    def reset_error_count
      redis.with { |r| r.del(error_count_key_name) }
    end

    def increase_error_count
      redis.with { |r| r.incr(error_count_key_name) }
    end

    def error_count
      redis.with { |r| (r.get(error_count_key_name) || 0).to_i }
    end

    ###

    def sync_interval
      @sync_interval ||= Rails.configuration.pompa.campaign.sync_interval
        .seconds
    end

    def respawn_interval
      @respawn_interval ||= Rails.configuration.pompa.campaign.respawn_interval
        .seconds
    end

    def victim_batch_size
      @victim_batch_size ||= Rails.configuration.pompa.campaign.victim_batch_size
    end

    def error_threshold
      @error_threshold ||= Rails.configuration.pompa.campaign.error_threshold
    end

    def public_redis_db
      @public_redis_db ||= Rails.configuration.pompa.campaign.public_redis_db.to_sym
    end

    ###

    def queued_victims_set_name
      self.class.queued_victims_set_name(instance_id)
    end

    def error_count_key_name
      self.class.error_count_key_name(instance_id)
    end
end
