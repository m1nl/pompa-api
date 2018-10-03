require 'pompa/middleware_wrapper'

if !Rails.configuration.pompa.origins.blank?
  public_url = "#{Rails.configuration.pompa.url}/public"

  Rails.application.config.middleware.insert_before(0,
    Pompa::MiddlewareWrapper, :middleware => Rack::Cors,
    :exclude => [/^#{public_url}/]) do
    allow do
      origins Rails.configuration.pompa.origins
      resource '*',
        headers: :any,
        methods: %i(get post put patch delete options head)
    end
  end
end
