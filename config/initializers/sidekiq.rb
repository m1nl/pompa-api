require 'pompa/redis_connection'

Sidekiq.configure_client do |config|
  config.redis = Pompa::RedisConnection.config(
    :db => Pompa::RedisConnection::SIDEKIQ_DB
  ).except(:pool_size)
end

Sidekiq.configure_server do |config|
  Rails.application.config.cache_classes = true
  Rails.application.config.eager_load = true

  ActiveRecord::Base.connection_pool.disconnect!

  ActiveSupport.on_load(:active_record) do
    active_record_config = ActiveRecord::Base.configurations
      .find_db_config(Rails.env).configuration_hash.deep_dup

    active_record_config['pool'] = config.concurrency

    ActiveRecord::Base.establish_connection(active_record_config.freeze)
  end

  config.redis = Pompa::RedisConnection.config(
    :db => Pompa::RedisConnection::SIDEKIQ_DB
  ).except(:pool_size)

  Sidekiq.logger.level = Rails.configuration.pompa.log_level.to_sym
end
