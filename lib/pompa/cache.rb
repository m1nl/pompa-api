module Pompa
  class Cache
    class << self
      def exist?(name, opts = {})
        Rails.cache.exist?(name, opts)
      end

      def fetch(key, opts = {})
        if enabled? && (opts[:condition].nil? || !!opts[:condition])
          Rails.cache.fetch(key, opts.merge(expires_in: expires_in)) {
            yield }
        else
          yield
        end
      end

      def read(key, opts = {})
        Rails.cache.read(key, opts)
      end

      def write(key, value, opts = {})
        Rails.cache.write(key, value, opts.merge(expires_in: expires_in))
      end

      def delete(key)
        Rails.cache.delete(key)
      end

      def expires_in
        @expires_in ||= Rails.configuration.pompa.model_cache.expire.seconds
      end

      def enabled?
        @enabled = Rails.configuration.pompa
          .model_cache.enable if @enabled.nil?
        @enabled
      end
    end
  end
end
