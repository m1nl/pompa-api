# frozen_string_literal: true

require 'concurrent'
require 'pompa/multi_logger'

module Pompa
  class ModelSync
    class << self
      include MultiLogger

      CHANNEL = 'model_sync'
      TIMEOUT = 30

      INIT = 'init'

      CREATE = 'create'
      DELETE = 'delete'
      UPDATE = 'update'

      OPERATIONS = [CREATE, DELETE, UPDATE].freeze

      UnsupportedDatabaseError = Class.new(StandardError)

      def process
        connection = nil
        pool = nil
        models = {}

        connection = ActiveRecord::Base.connection_pool.checkout.tap do |c|
          ActiveRecord::Base.connection_pool.remove(c)
        end

        connection = connection.raw_connection

        if !connection.is_a?(PG::Connection)
          raise(UnsupportedDatabaseError, 'Only PostgreSQL database backend is supported')
        end

        pool = Concurrent::ThreadPoolExecutor.new(
          min_threads: 1,
          max_threads: Concurrent.processor_count * 2,
          max_queue: 0,
        )

        connection.async_exec("LISTEN #{CHANNEL}")
        logger.info{"Listening on #{CHANNEL} channel"}

        loop do
          connection.wait_for_notify(TIMEOUT) do |channel, pid, payload|
            operation, model_name, instance_id = payload.split(' ')
            instance_id = instance_id.to_i

            next if !OPERATIONS.include?(operation)
            next if instance_id == 0

            model = models[model_name]

            begin
              model ||= model_name.singularize.camelize.constantize
              models[model_name] = model
            rescue NameError
              logger.error{"Invalid model name #{model_name}"};
              models[model_name] = nil
              next
            end

            logger.debug{"Performing #{operation} for #{model} ##{instance_id}"}

            pool.post do
              unless !!Thread.current[INIT]
                logger.push_tags(TAG, "TID-#{Thread.current.object_id}")
                Thread.current[INIT] = true
              end

              begin
                case operation
                  when CREATE
                    if model < WorkerModel
                      model.start_worker(instance_id,
                        :force => true) if model.worker_auto_start?
                    end
                  when DELETE
                    if model < Model
                      model.reset_cached_key(instance_id)
                    end

                    if model < WorkerModel
                      model.stop_worker(instance_id,
                        :discard => true)
                    end
                  when UPDATE
                    if model < Model
                      model.reset_cached_key(instance_id)
                    end
                end

              logger.debug{"Operation #{operation} for #{model} ##{instance_id} performed"}

              rescue StandardError => e
                logger.error{"Operation #{operation} for #{model} ##{instance_id} failed with #{e.message}"}
                logger.multi_logger.backtrace(e)
              end
            end
          end
        end

        ensure
          if !connection.nil?
            begin connection.async_exec('UNLISTEN *') rescue StandardError end
            begin connection.disconnect! rescue StandardError end
          end

          if !pool.nil?
            pool.shutdown
            pool.wait_for_termination
          end
       end
    end
  end
end
