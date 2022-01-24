require 'pompa/redis_connection'

Sidekiq.configure_client do |config|
  config.redis = Pompa::RedisConnection.pool(
    :db => Pompa::RedisConnection::SIDEKIQ_DB
  )
end

Sidekiq.configure_server do |config|
  Rails.application.config.cache_classes = true
  Rails.application.config.eager_load = true

  config.redis = Pompa::RedisConnection.pool(
    :db => Pompa::RedisConnection::SIDEKIQ_DB,
    :pool_size => pool_size,
  )

  Sidekiq.logger.level = Rails.configuration.pompa.log_level.to_sym
end
