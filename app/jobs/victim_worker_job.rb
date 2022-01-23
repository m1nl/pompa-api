class VictimWorkerJob < WorkerJob
  TIMEOUT_ERROR = 'Timeout waiting for mailer response'.freeze

  queue_as :victims

  class << self
    def cleanup(opts)
      Pompa::RedisConnection.redis(opts) do |r|
        r.del(retry_count_key_name(opts[:instance_id]))
      end
    end

    def retry_count_key_name(instance_id, name = self.name)
      "#{name}:#{instance_id}:retry_count"
    end
  end

  protected
    def finished?
      super || model.worker_finished?
    end

    def tick
      if model.state == Victim::QUEUED &&
        model.updated_at < (email_timeout * 1.2).seconds.ago
        model.with_lock do
          model.state = Victim::ERROR
          model.last_error = TIMEOUT_ERROR
          model.error_count += 1
          model.save!
        end

        logger.error("Email sending error: #{model.last_error}")
        return result(ERROR, model.last_error, :broadcast => true)
      end
    end

    def process(message)
      return process_result(message) if message[:result].is_a?(Hash)
      return process_action(message) if !message[:action].blank?
      return result(INVALID, 'Invalid message');
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
        'Unable to process result') if origin_name != MailerWorkerJob.name

      model.with_lock do
        return result(INVALID,
          'Unable to process result') if model.state != Victim::QUEUED

        case status
          when Mailer::QUEUED
            model.message_id = value
            model.save!
            return result(SUCCESS)
          when Mailer::SENT
            return result(INVALID,
              'Invalid Message-ID') if !model.message_id.blank? &&
              model.message_id != value

            model.state = Victim::SENT
            model.message_id = value
            model.sent_date = Time.current
            model.last_error = nil
            model.save!
            return result(Victim::STATE_CHANGE, model.state, :broadcast => true)
          when ERROR
            if retry_count >= retry_threshold
              model.state = Victim::ERROR
              model.last_error = value
              model.error_count += 1
              model.save!

              logger.info('Maximum number of retries exceeded')
              return result(ERROR, model.last_error, :broadcast => true)
            else
              increase_retry_count
              logger.info("Retrying - #{retry_count}/#{retry_threshold}")
              return process_email
            end
          when INVALID
            model.state = Victim::ERROR
            model.last_error = value
            model.error_count += 1
            model.save!
            return result(ERROR, model.last_error, :broadcast => true)
          else
            return result(SUCCESS) # ignore
        end
      end
    end

    def process_action(message)
      action = message.dig :action
      return result(INVALID, 'Invalid action') if action.blank?

      case action
        when Victim::SEND
          return send_email(message)
        when Victim::RESET
          return reset_state(message)
      end

      return result(INVALID, 'Unable to process action')
    end

    def send_email(message)
      model.with_lock do
        return result(INVALID, 'Campaign has finished') if model.scenario
          .campaign.state == Campaign::FINISHED
        return result(INVALID, 'Invalid state') if ![Victim::PENDING,
          Victim::ERROR].include?(model.state) && !message[:force]

        reset_retry_count
        return process_email
      end
    end

    def reset_state(message)
      model.with_lock do
        return result(INVALID, 'Campaign has finished') if model.scenario
          .campaign.state == Campaign::FINISHED
        return result(INVALID, 'Invalid state') if ![Victim::SENT,
          Victim::ERROR].include?(model.state) && !message[:force]

        model.state = Victim::PENDING
        model.last_error = nil
        model.error_count = 0
        model.save!
      end

      model.scenario.campaign.ping
      return result(Victim::STATE_CHANGE, model.state)
    end

    def process_email
      model.with_lock do
        begin
          logger.debug('Preparing email')
          @mail = model.mail
          multi_logger.debug{['Queueing email: ', @mail]}
          model
            .scenario
            .mailer
            .message(
              {
                :mail => @mail,
                :reply_to => message_queue_key_name,
                :expires => email_timeout.from_now,
              }, { :pool => redis })
          logger.info('Email queued')
          model.state = Victim::QUEUED
          model.save!
          return result(Victim::STATE_CHANGE, model.state, :broadcast => true)
        rescue StandardError => e
          model.state = Victim::ERROR
          model.last_error = "#{e.class}: #{e.message}"
          model.error_count += 1
          logger.error("Error preparing email: #{model.last_error}")
          multi_logger.backtrace(e)
          return result(ERROR, model.last_error, :broadcast => true)
        end
      end
    end

    ###

    def reset_retry_count
      redis.with { |r| r.del(retry_count_key_name) }
    end

    def increase_retry_count
      redis.with { |r| r.incr(retry_count_key_name) }
    end

    def retry_count
      redis.with { |r| (r.get(retry_count_key_name) || 0).to_i }
    end

    ###

    def email_timeout
      @email_timeout ||= Rails.configuration.pompa.victim.email_timeout.seconds
    end

    def retry_threshold
      @retry_threshold ||= Rails.configuration.pompa.victim.retry_threshold
    end

    ###

    def retry_count_key_name
      self.class.retry_count_key_name(instance_id)
    end
end
