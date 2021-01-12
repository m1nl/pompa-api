require 'pompa/redis_connection'

Sidekiq.configure_client do |config|
  config.redis = Pompa::RedisConnection.pool
end

Sidekiq.configure_server do |config|
  Rails.application.config.cache_classes = true
  Rails.application.config.eager_load = true

  ActiveRecord::Base.connection_pool.disconnect!

  ActiveSupport.on_load(:active_record) do
    active_record_config = (ActiveRecord::Base.configurations[Rails.env] ||
      Rails.application.config.database_configuration[Rails.env]).deep_dup
    active_record_config['pool'] = Sidekiq.options[:concurrency] + 5

    ActiveRecord::Base.establish_connection(active_record_config.freeze)
  end

  Pompa::RedisConnection.pool_size = Sidekiq.options[:concurrency] + 5
  config.redis = Pompa::RedisConnection.pool
end
