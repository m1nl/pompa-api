module Pompa
  class MiddlewareWrapper
    def initialize(app, opts = {}, &block)
      @app = app
  
      @middleware_class = opts.delete(:middleware)
      @include = Array(opts.delete(:include))
      @exclude = Array(opts.delete(:exclude))
  
      @middleware = @middleware_class.new(app, opts, &block)
    end
  
    def call(env)
      req = Rack::Request.new(env)
      path = req.path

      return @app.call(env) if path.nil?

      if (@include.empty? || @include.any? { |r| path.match(r) }) &&
        (@exclude.empty? || @exclude.none? { |r| path.match(r) })
        @middleware.call(env)
      else
        @app.call(env)
      end
    end
  end
end
