require 'pompa/redis_connection'

Sidekiq.configure_client do |config|
  config.redis = Pompa::RedisConnection.pool(
    :db => Pompa::RedisConnection::SIDEKIQ_DB
  )
end

Sidekiq.configure_server do |config|
  Rails.application.config.cache_classes = true
  Rails.application.config.eager_load = true

  ActiveRecord::Base.connection_pool.disconnect!

  pool_size = Sidekiq.options[:concurrency] + 5

  ActiveSupport.on_load(:active_record) do
    active_record_config = (ActiveRecord::Base.configurations[Rails.env] ||
      Rails.application.config.database_configuration[Rails.env]).deep_dup
    active_record_config['pool'] = pool_size

    ActiveRecord::Base.establish_connection(active_record_config.freeze)
  end

  config.redis = Pompa::RedisConnection.pool(
    :db => Pompa::RedisConnection::SIDEKIQ_DB,
    :pool_size => pool_size,
  )
end
