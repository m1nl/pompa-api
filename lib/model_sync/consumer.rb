# frozen_string_literal: true

module ModelSync
  class Consumer
    NAME = 'consumer'

    def initialize
      @done = false
      @mutex = Mutex.new
      @models = {}
    end

    def run
      @mutex.synchronize do
        stop if alive?

        @thread = Thread.new do 
          Thread.current[:name] = NAME
          consumer_thread
        rescue Exception => e
          logger.error("#{e.class.name}: #{e.message}")
          logger.backtrace(e)
          raise e
        end
      end
    end

    def stop
      @mutex.synchronize do 
        @done = true

        if !@thread.nil? && @thread.alive?
          if block_given? then yield else sleep ModelSync:TIMEOUT end

          @thread.raise Interrupt if alive?
        end

        ensure
          @thread = nil
          @done = false
      end
    end

    def alive?
      !@thread.nil? && @thread.alive?
    end

    def name
      NAME
    end

    private
      def logger
        ModelSync.logger
      end

      def multi_logger
        logger.multi_logger
      end
 
      def done?
        @done
      end

      def consumer_thread
       logger.info("Consumer thread started")

        message_queue = Redis::Queue.new(ModelSync::QUEUE,
          ModelSync::PROCESS_QUEUE, :redis => Pompa::RedisConnection.get,
          :timeout => ModelSync::TIMEOUT)

        logger.info("Bound to #{ModelSync::QUEUE} with #{ModelSync::TIMEOUT}s timeout")
 
        loop do
          break if done?

          json = message_queue.pop
          break if done?

          next if json.blank?

          hash = {}

          begin
            hash = Oj.load(json, symbol_keys: true)
          rescue Oj::ParseError => e
            logger.error{"Unable to parse \"#{json}\" as JSON: #{e.message}"}
            message_queue.commit
            next
          end

          model_name = hash[:model_name]
          operation = hash[:operation]
          instance_id = hash[:instance_id]

          model = @models[model_name]
 
          begin
            model ||= model_name.singularize.camelize.constantize
            @models[model_name] = model
          rescue NameError
            logger.error{"Invalid model name \"#{model_name}\""};
            @models[model_name] = nil
            message_queue.commit
            next
          end
 
          logger.debug{"Performing operation \"#{operation}\" for #{model} ##{instance_id}"}
 
          begin
            case operation
              when ModelSync::CREATE
                if model < WorkerModel
                  model.start_worker(instance_id,
                    :force => true) if model.worker_auto_start?
                end
              when ModelSync::DELETE
                if model < Model
                  model.reset_cached_key(instance_id)
                end

                if model < WorkerModel
                  model.stop_worker(instance_id,
                    :discard => true)
                end
              when ModelSync::UPDATE
                if model < Model
                  model.reset_cached_key(instance_id)
                end
             end

          logger.debug{"Operation \"#{operation}\" for #{model} ##{instance_id} performed"}
          message_queue.commit

          rescue StandardError => e
            logger.error{"Operation \"#{operation}\" for #{model} ##{instance_id} failed with #{e.message}"}
            logger.backtrace(e)
          end
        end
        rescue Interrupt
        rescue Redis::CannotConnectError => e
          logger.error{"Error #{e.class}: #{e.message}"}
          logger.backtrace(e)
        ensure
          logger.info("Consumer thread stopped")
      end
   end
end

