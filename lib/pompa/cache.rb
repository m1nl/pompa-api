module Pompa
  class Cache
    class << self
      def exist?(key, opts = {})
        return false if key.blank?

        Rails.cache.exist?(key, opts)
      end

      def fetch(key, opts = {})
        return yield if key.blank?

        if enabled? && (opts[:condition].nil? || !!opts[:condition])
          Rails.cache.fetch(key, opts.merge(expires_in: expires_in)) { yield }
        else
          yield
        end
      end

      def read(key, opts = {})
        return nil if key.blank?

        Rails.cache.read(key, opts)
      end

      def write(key, value, opts = {})
        return nil if key.blank?

        Rails.cache.write(key, value, opts.merge(expires_in: expires_in))
      end

      def delete(key)
        return nil if key.blank?

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
