require 'oj'
require 'mail'
require 'ihasa'
require 'securerandom'
require 'base64'

Mail.eager_autoload!

class MailerWorkerJob < WorkerJob
  include Mail::Utilities

  TEXT_PLAIN_CONTENT_TYPE = 'text/plain'
  TEXT_PLAIN_CONTENT_TYPE_WITH_CHARSET = 'text/plain; charset=UTF-8'.freeze

  HTML_CONTENT_TYPE = 'text/html'.freeze
  HTML_CONTENT_TYPE_WITH_CHARSET = 'text/html; charset=UTF-8'.freeze

  MULTIPART_RELATED_CONTENT_TYPE = 'multipart/related'.freeze
  MULTIPART_ALTERNATIVE_CONTENT_TYPE = 'multipart/alternative'.freeze
  MULTIPART_MIXED_CONTENT_TYPE = 'multipart/mixed'.freeze

  IHASA_PREFIX = "#{self.name}:#{Ihasa::Bucket.name}:%s"

  SORT_ORDER = [MULTIPART_MIXED_CONTENT_TYPE,
    MULTIPART_ALTERNATIVE_CONTENT_TYPE, TEXT_PLAIN_CONTENT_TYPE,
    MULTIPART_RELATED_CONTENT_TYPE, HTML_CONTENT_TYPE].freeze

  PLAIN = 'plain'.freeze
  NONE = 'none'.freeze
  INLINE = 'inline'.freeze

  CONTENT_ID_HEADER = 'Content-ID'.freeze
  CONTENT_DISPOSITION_HEADER = 'Content-Disposition'.freeze

  SMTPS_PORT = 465

  MIN_QUEUE_TIMEOUT = 5.seconds
  MIN_BLOCK_TIME = 0.001.seconds

  queue_as :mailers

  class << self
    def cleanup(opts)
      Pompa::RedisConnection.redis(opts) do |r|
        r.del(mail_queue_key_name(opts[:instance_id]))
      end
    end

    def mail_queue_key_name(instance_id, name = self.name)
      "#{name}:#{instance_id}:mail_queue"
    end
  end

  protected
    def resync
      super

      @bucket = nil
      @block_time = MIN_BLOCK_TIME

      if !model.per_minute.nil? && model.per_minute > 0
        rate = model.per_minute / 60.0
        burst = model.burst || 1
        @bucket = Ihasa.bucket(rate: rate, burst: burst,
          prefix: IHASA_PREFIX % SecureRandom.uuid,
          redis: Pompa::RedisConnection.get)
        @block_time = [block_time,
          [(1.05 / rate).seconds, idle_timeout / 2].min].max
        @block_time = block_time.ceil(3)
      end

      self.queue_timeout = [block_time.round, MIN_QUEUE_TIMEOUT].max

      logger.info("Throttling: #{( bucket.nil? ? "off" : "on" )}, " \
        "block time: #{block_time}s, queue timeout: #{self.queue_timeout}s")

      return model
    end

    def finished?
      redis.with do |r|
        super || (idle_for > idle_timeout && r.llen(mail_queue_key_name) == 0)
      end
    end

    def invoke(opts = {})
      @elapsed = 0
      @deliveries = 0
    end

    def tick
      redis.with do |r|
        starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        messages_num = 0

        while message_queue.length == 0 do
          json = r.rpop(mail_queue_key_name)
          break if json.nil?

          mark

          begin
            mail = Oj.load(json, symbol_keys: true)
          rescue Oj::ParseError => e
            logger.error("Ignoring invalid queued email")
            next
          end

          while (!bucket.nil? && !bucket.accept?)
            sleep(block_time)
          end

          response(deliver(mail), mail[:reply_to])
          messages_num += 1
        end

        if messages_num > 0
          ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          @elapsed += ending - starting
          @deliveries += messages_num

          messages_per_minute = (60 / (@elapsed / @deliveries)).round

          multi_logger.info("Processed #{@deliveries} messages in " +
            "#{@elapsed.round(2)}s so far (#{messages_per_minute} per minute)")
        end

        mark if r.llen(mail_queue_key_name) > 0
      end
    end

    def process(message)
      return process_mail(message) if message[:mail].is_a?(Hash)
      return result(INVALID, 'Invalid message')
    end

  private
    def process_mail(message)
      mail = message[:mail]
      mail[:message_id] ||= generate_message_id(mail)
      mail[:reply_to] = message[:reply_to]

      redis.with { |r| r.lpush(mail_queue_key_name, mail.to_json) }
      multi_logger.debug{["Queued email #{mail[:message_id]}: ", mail]}
      return result(Mailer::QUEUED, mail[:message_id])
    end

    def generate_message_id(mail)
      address = Mail::Address.new(mail[:sender_email] ||
        model.sender_email || '')
      return SecureRandom.uuid if address.domain.blank?

      "#{SecureRandom.uuid}@#{address.domain}"
    end

    def deliver(raw_mail)
      multi_logger.info{["Delivering email #{raw_mail[:message_id]}: ",
        raw_mail]}

      mail = Mail.new

      address = Mail::Address.new
      address.address = raw_mail[:recipient_email] || ''
      address.display_name = raw_mail[:recipient_name] || ''

      if address.address.blank?
        logger.error('No recipient address specified - ignoring e-mail')
        return result(INVALID, 'No recipient address specified')
      end

      mail.to = address.format
      mail.smtp_envelope_to = address.address

      address = Mail::Address.new
      address.address = raw_mail[:sender_email] ||
        model.sender_email || ''
      address.display_name = raw_mail[:sender_name] ||
        model.sender_name || ''

      if address.address.blank?
        logger.error('No sender address specified - ignoring e-mail')
        return result(INVALID, 'No sender address specified')
      end

      mail.from = address.format
      mail.smtp_envelope_from = address.address
      sender_domain = address.domain

      mail.message_id = bracket(raw_mail[:message_id] ||
        generate_message_id(raw_mail))
      mail.subject = raw_mail[:subject] || ''

      plaintext = raw_mail[:plaintext] || ''
      html = raw_mail[:html] || ''

      headers = raw_mail[:headers] || {}

      attachments = []
      inline = []

      if raw_mail[:attachments].is_a?(Array)
        raw_mail[:attachments].each do |a|
          next if !a.is_a?(Hash)
          next if a[:filename].blank?
          next if a[:content].blank?

          attachment = {
            :filename => a[:filename],
            :content => Base64.decode64(a[:content]),
            :inline => !!a[:inline],
          }

          attachment.merge!(:mime_type =>
            a[:content_type]) if !a[:content_type].blank?
          attachment.merge!(:content_id =>
            a[:content_id]) if !a[:content_id].blank?

          (attachment[:inline] ? inline : attachments) << attachment
        end
      end

      plaintext_part = Mail::Part.new do
        content_type TEXT_PLAIN_CONTENT_TYPE_WITH_CHARSET
        body plaintext
      end unless plaintext.blank?

      html_part = Mail::Part.new do
        content_type HTML_CONTENT_TYPE_WITH_CHARSET
        body html
      end unless html.blank?

      html_part = if html_part.nil? || inline.empty?
          html_part
        else
          Mail::Part.new do |p|
            p.content_type MULTIPART_RELATED_CONTENT_TYPE
            p.add_part html_part
            inline.each do |a|
              p.attachments[a[:filename]] = a.except(*[:filename,
                :content_id, :inline])
              p.attachments[a[:filename]].header[CONTENT_ID_HEADER] =
                bracket(a[:content_id] ||
                "#{SecureRandom.uuid}@#{sender_domain}")
              p.attachments[a[:filename]].header[CONTENT_DISPOSITION_HEADER] =
                INLINE
            end
          end
        end

      body_part = if !html_part.nil? && !plaintext_part.nil?
          Mail::Part.new do
            content_type MULTIPART_ALTERNATIVE_CONTENT_TYPE
            add_part plaintext_part
            add_part html_part
          end
        elsif html_part.nil?
          plaintext_part
        else plaintext_part.nil?
          html_part
        end

      body_part = Mail::Part.new do
          content_type TEXT_PLAIN_CONTENT_TYPE_WITH_CHARSET
          body ''
        end if body_part.nil?

      body_part = if attachments.empty?
          body_part
        else
          Mail::Part.new do |p|
            p.content_type MULTIPART_MIXED_CONTENT_TYPE
            p.add_part body_part
            attachments.each do |a|
              p.attachments[a[:filename]] = a.except(*[:filename,
                :content_id, :inline])
              p.attachments[a[:filename]].header[CONTENT_ID_HEADER] =
                bracket(a[:content_id] ||
                "#{SecureRandom.uuid}@#{sender_domain}")
            end
          end
        end

      if headers.is_a?(Hash)
        headers.each { |k, v| mail.header[k.to_s] = v }
      end

      mail.content_type = body_part.content_type

      mail.body = body_part.body.raw_source
      mail.body.set_sort_order(SORT_ORDER)

      body_part.parts.each do |p|
        mail.add_part(p)
      end

      mail.delivery_method(:smtp, {
          :address => model.host,
          :port => model.port,
          :user_name => model.username,
          :password => model.password,
          :ssl => model.port == SMTPS_PORT,
          :authentication => PLAIN,
          :openssl_verify_mode => (NONE if model.ignore_certificate),
          :enable_starttls_auto => true
      })

      begin
        multi_logger.debug{["Email content:\n", mail.to_s]} if debug_email_content?

        mail.deliver!
        logger.info("Email #{mail.message_id} delivered")
        return result(Mailer::SENT, mail.message_id)
      rescue StandardError => e
        logger.error("Email #{mail.message_id} delivery error: #{e.class.name}: #{e.message}")
        multi_logger.backtrace(e)
        return result(ERROR, "#{e.class.name}: #{e.message}")
      end
    end

    ###

    def bucket
      @bucket
    end

    def block_time
      @block_time
    end

    ###

    def idle_timeout
      @idle_timeout ||= Rails.configuration.pompa.mailer.idle_timeout.seconds
    end

    def debug_email_content?
      @debug_email_content ||= Rails.configuration.pompa.mailer.debug_email_content
    end

    ###

    def mail_queue_key_name
      self.class.mail_queue_key_name(instance_id)
    end
end
