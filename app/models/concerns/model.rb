module Model
  extend ActiveSupport::Concern

  ID = 'id'.freeze
  CACHE_PATH = 'cache_path'.freeze
  CACHE_KEY = 'cache_key'.freeze
  TIMESTAMP = 'timestamp'.freeze

  def build_model!(model = {}, opts = {})
    name = self.class.name.underscore

    opts[:ignore] = Array(opts[:ignore])
    return model if (!model[name].nil? && model.dig(name, ID) == id)
    return model if Array(opts[:ignore]).include?(name.to_sym)

    if !opts[:shallow]
      self.class.build_model_prepend.each do |m|
        association = self.class.reflect_on_association(m)
        association.klass.build_model!(
          attributes[association.foreign_key], model, opts)
      end
    end

    cache_path = "#{cache_key}"
    cache_path =
      "#{model[CACHE_PATH]}/#{cache_path}" if !model[CACHE_PATH].blank?

    model[name] = {}
    model[name][CACHE_KEY] = cache_key
    model[name][TIMESTAMP] = updated_at

    serialize_model!(name, model, opts)
    Pompa::Cache.write(cache_path, model[name]) if Pompa::Cache.enabled?

    model[CACHE_PATH] = cache_path

    if model[TIMESTAMP].nil? || !model[TIMESTAMP].is_a?(Time)
      model[TIMESTAMP] = model[name][TIMESTAMP]
    else
      model[TIMESTAMP] = [model[TIMESTAMP], model[name][TIMESTAMP]].max
    end

    if !opts[:shallow]
      self.class.build_model_append.each do |m|
        association = self.class.reflect_on_association(m)
        association.klass.build_model!(
          attributes[association.foreign_key], model, opts)
      end
    end

    return model
  end

  def build_model(model = {}, opts = {})
    build_model!(model.dup, opts)
  end

  class_methods do
    def cached_key(id, opts = {})
      return nil if id.nil?

      @cache_enable = Rails.configuration.pompa
        .model_cache.enable if @cache_enable.nil?
      @cache_expire ||= Rails.configuration.pompa
        .model_cache.expire.seconds

      if @cache_enable
        Pompa::RedisConnection.redis(opts) do |r|
          return r.get(cached_key_name(id)) if r.exists(cached_key_name(id))

          opts[:model] = find_by_id(id)
          return nil if opts[:model].nil?

          cache_key = opts[:model].cache_key
          r.setex(cached_key_name(id), @cache_expire, cache_key)
          return cache_key
        end
      else
        opts[:model] ||= find_by_id(id)
        return nil if opts[:model].nil?

        opts[:model].cache_key
      end
    end

    def reset_cached_key(id, opts = {})
      Pompa::RedisConnection.redis(opts) do |r|
        r.pipelined do |p|
          Array(id).each { |i| p.del(cached_key_name(i)) }
        end
      end
    end

    def exists?(id_or_conditions)
      @cache_enable = Rails.configuration.pompa
        .model_cache.enable if @cache_enable.nil?

      if id_or_conditions.is_a?(Integer) && @cache_enable
        return true if !cached_key(id_or_conditions).nil?
      end

      super(id_or_conditions)
    end

    def build_model!(id, model = {}, opts = {})
      name = self.name.underscore

      opts[:ignore] = Array(opts[:ignore])
      return model if (!model[name].nil? && model.dig(name, ID) == id)
      return model if opts[:ignore].include?(name.to_sym)

      if !opts[:shallow]
        if !build_model_prepend.empty?
          ids = Array(where(id: id).limit(1).pluck(*
            build_model_prepend.map do |m|
              reflect_on_association(m).foreign_key
            end
          ).first)
          return nil if ids.empty?

          ids = Hash[build_model_prepend.zip ids]

          build_model_prepend.each do |m|
            association = reflect_on_association(m)
            association.klass.build_model!(ids[m], model, opts)
          end
        end
      end

      opts.delete(:model)

      cache_path = "#{cached_key(id, opts)}"
      cache_path =
        "#{model[CACHE_PATH]}/#{cache_path}" if !model[CACHE_PATH].blank?

      if (Pompa::Cache.enabled? && Pompa::Cache.exist?(cache_path))
        model[name] = Pompa::Cache.read(cache_path)
      else
        opts[:model] ||= find_by_id(id)
        return nil if opts[:model].nil?

        model[name] = {}
        model[name][CACHE_KEY] = opts[:model].cache_key
        model[name][TIMESTAMP] = opts[:model].updated_at

        opts[:model].serialize_model!(name, model, opts)
        Pompa::Cache.write(cache_path, model[name]) if Pompa::Cache.enabled?
      end

      model[CACHE_PATH] = cache_path

      if model[TIMESTAMP].nil? || !model[TIMESTAMP].is_a?(Time)
        model[TIMESTAMP] = model[name][TIMESTAMP]
      else
        model[TIMESTAMP] = [model[TIMESTAMP], model[name][TIMESTAMP]].max
      end

      opts.delete(:model)

      if !opts[:shallow]
        build_model_append.each do |m|
          association = reflect_on_association(m)
          association.klass.build_model!(
            model.dig(name, association.foreign_key), model, opts)
        end
      end

      return model
    end

    def build_model(id, model = {}, opts = {})
      build_model!(id, model.dup, opts)
    end

    def build_model_prepend(*models)
      @build_model_prepend ||= []
      @build_model_prepend.push(*models) if !models.empty?
      @build_model_prepend
    end

    def build_model_append(*models)
      @build_model_append ||= []
      @build_model_append.push(*models) if !models.empty?
      @build_model_append
    end

    def cached_key_name(id)
      "#{name}:#{id}:cached_key"
    end
  end

  def serialize_model!(name, model, opts)
    true
  end
end
