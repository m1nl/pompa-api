require 'pompa'

Sidekiq.configure_client do |config|
  config.redis = Pompa::RedisConnection.common_pool
end

Sidekiq.configure_server do |config|
  Rails.application.config.cache_classes = true
  Rails.application.config.eager_load = true

  ActiveRecord::Base.configurations[Rails.env]['pool'] = Sidekiq.options[:concurrency] + 5
  config.redis = Pompa::RedisConnection.pool(size: Sidekiq.options[:concurrency] + 5)
end
