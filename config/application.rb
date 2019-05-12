require_relative 'boot'

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
# require "action_view/railtie"
# require "action_cable/engine"
# require "sprockets/railtie"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module PompaApi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 6.0

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    # Custom configuration
    config.pompa = Hashie::Mash.new(Rails.application.config_for(:pompa_defaults))
    config.pompa.merge!(Hashie::Mash.new(Rails.application.config_for(:pompa)))

    # Use SQL for ActiveRecord schema
    config.active_record.schema_format = :sql

    # Use sidekiq for ActiveJob
    config.active_job.queue_adapter = :sidekiq

    # Perform strict checking for Liquid templates
    Liquid::Template.error_mode = :strict

    # Include lib directory for extra classes
    config.autoload_paths << Rails.root.join('lib')

    # Add cookie middleware
    config.middleware.use ActionDispatch::Cookies

    # Configuration for trusted proxies
    if !Rails.configuration.pompa.trusted_proxies.nil?
      require 'resolv'

      ips = []

      Rails.configuration.pompa.trusted_proxies.map do |name|
        ip = IPAddr.new(name) rescue nil
        ip = Resolv.getaddresses(name).map { |i|
          IPAddr.new(i) } if ip.nil?
        ips << ip if !ip.nil?
      end

      config.action_dispatch.trusted_proxies = ips.flatten.uniq
    end

    # Configure log level
    config.log_level = Rails.configuration.pompa.log_level.to_sym

    # Enable verbose query logs (only in debug log level)
    config.active_record.verbose_query_logs = true

    # Specifies the header that your server uses for sending files
    config.action_dispatch.x_sendfile_header = Rails.configuration.pompa
      .sendfile_header if !Rails.configuration.pompa.sendfile_header.blank?
  end
end
