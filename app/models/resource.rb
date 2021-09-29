require 'http'
require 'liquid'
require 'tempfile'

class Resource < ApplicationRecord
  include Defaults
  include Pageable
  include LiquidTemplate
  include Model

  FILE = 'file'.freeze
  URL = 'url'.freeze
  EMPTY = 'empty'.freeze
  RESOURCE = 'resource'.freeze
  EXTENSION = 'extension'.freeze
  CONTENT_TYPE = 'content_type'.freeze

  DEFAULT_CONTENT_TYPE = 'application/octet-stream'.freeze
  DEFAULT_EXTENSION = '.bin'.freeze

  CONTENT_TYPE_HEADER_LOWERCASE = 'content-type'.freeze

  NAME = 'name'.freeze

  belongs_to :template, required: true

  validates :name, :code, presence: true
  validates :url, :url => { :allow_nil => true, :allow_blank => true }

  has_one_attached :file

  validate :transforms_check

  default :code, proc { Pompa::Utils.random_code }

  build_model_prepend :template

  after_commit :clear_cached_values

  liquid_template :url
  liquid_template :content, :readonly => true, :validate => false,
    :cache_condition => -> { type != URL || !dynamic_url? }

  def dynamic?
    (type == URL && dynamic_url?) || render_template? || !transforms.blank?
  end

  def static?
    !dynamic?
  end

  def file=(value)
    result = super(value)

    if file.attached?
      self[:url] = nil
      dynamic_url = false
    end

    @real_content_type = nil

    result
  end

  def url=(value)
    self[:url] = value
    file.purge unless value.blank?

    @real_content_type = nil

    value
  end

  def type
    return FILE if file.attached?
    return URL if !url.blank?
    return EMPTY
  end

  def render(model = {}, opts = {})
    full_model = build_model(model, opts) if dynamic?

    if render_template?
      content_template = content_template(full_model, opts)

      full_model.except!(RESOURCE)
      content_rendered = content_template.render!(full_model,
        template.liquid_flags(full_model, opts))

      content_call = lambda { |&block| block.call(content_rendered) }
    else
      content_call = lambda { |&block| content(full_model, opts, &block) }
    end

    if block_given?
      transform_content(content_call, full_model, opts) { |c| yield c }
    else
      transform_content(content_call, full_model, opts)
    end
  end

  def content(model = {}, opts = {})
    case type
      when FILE
        if block_given?
          file.download do |c|
            yield c
          end
        else
          return file.download
        end
      when URL
        if dynamic_url?
          full_model = build_model(model, opts) if dynamic?
          content_url = full_model.dig(RESROUCE, URL)
        end

        content_url ||= url

        http = HTTP.get(content_url)
        headers = http.headers
        @real_content_type = content_type ||
          extract_content_type(headers[CONTENT_TYPE_HEADER_LOWERCASE]) ||
          DEFAULT_CONTENT_TYPE
        body = http.body

        if block_given?
          body.each { |c| yield c }
        else
          body.to_s
        end
    end
  end

  def real_content_type(model = {}, opts = {})
    return @real_content_type if !@real_content_type.blank?

    @real_content_type = self.content_type

    if @real_content_type.blank?
      case type
        when FILE
          @real_content_type = file.content_type
        when URL
          if dynamic_url?
            full_model = build_model(model, opts) if dynamic?
            content_url = full_model.dig(RESOURCE, URL)
          end

          content_url ||= url

          http = HTTP.head(content_url)
          headers = http.headers
          @real_content_type = extract_content_type(
            headers[CONTENT_TYPE_HEADER_LOWERCASE])
      end
    end

    @real_content_type = DEFAULT_CONTENT_TYPE if @real_content_type.blank?
    @real_content_type = @real_content_type.downcase

    @real_content_type
  end

  def real_extension(model = {}, opts = {})
    return @real_extension if !@real_extension.blank?

    @real_extension = self.extension

    if (@real_extension.blank? && type == FILE)
      @real_extension = File.extname(file.filename.sanitized)
    end

    if @real_extension.blank?
      @real_extension = Rack::Mime::MIME_TYPES
        .invert[real_content_type(model, opts)]
    end

    @real_extension = DEFAULT_EXTENSION if @real_extension.blank?
    @real_extension = @real_extension.downcase

    @real_extension
  end

  class ContentWrapper
    def initialize(resource, opts = {})
      @resource = resource
      @model = opts.delete(:model) || {}
      @render = !!opts.delete(:render)
      @error_handler = opts.delete(:error_handler)
    end

    def each
      @resource.public_send(@render ? :render : :content, @model) { |c| yield c }
    rescue StandardError => e
      unless @error_handler.nil?
        yield @error_handler.call(e)
      else
        raise e
      end
    end
  end

  def dup
    super.tap do |c|
      c.code = Pompa::Utils.random_code

      if type == FILE
        tempfile = Tempfile.new(RESOURCE)
        tempfile.binmode

        begin
          file.blob.download { |f| tempfile.write(f) }
          tempfile.rewind

          blob = ActiveStorage::Blob.create_and_upload!(
            io: tempfile,
            filename: file.blob.filename,
            content_type: file.blob.content_type,
            identify: false
          )
          blob.analyze

          c.file.purge
          c.file.attach(blob)
        ensure
          tempfile.unlink
        end
      end
    end
  end

  def clear_cached_values
    self.class.clear_cached_values(code)
  end

  class << self
    def id_by_code(resource_code)
      Pompa::Cache.fetch("resource_#{resource_code}/id") do
        Resource.where(code: resource_code).pick(:id)
      end
    end

    def template_id_by_code(resource_code)
      Pompa::Cache.fetch("resource_#{resource_code}/template_id") do
        Resource.where(code: resource_code).pick(:template_id)
      end
    end

    def clear_cached_values(resource_code)
      Pompa::Cache.delete("resource_#{resource_code}/id")
      Pompa::Cache.delete("resource_#{resource_code}/template_id")
    end

    def register_transform(clazz)
      @transforms ||= {}
      @transforms[clazz.name.demodulize.underscore] = clazz
    end

    def transform_class(name)
      @transforms ||= {}
      @transforms[name]
    end
  end

  def serialize_model!(name, model, opts)
    model[name].merge!(
      ResourceSerializer.new(self).serializable_hash(:include => [])
        .except!(*[:url, :content_type, :extension, :links])
        .deep_stringify_keys
    )

    model[name].merge!(
       {
         CONTENT_TYPE => real_content_type(model, opts),
         EXTENSION => real_extension(model, opts),
       }
    )

    if type == URL
      model[name].merge!(
        { URL => url_template.render!(model, Pompa::Utils.liquid_flags) }
      )
    end

    transform_model!(name, model, opts) if !opts[:skip_transforms]
  end

  private
    def transform_content(input, model = {}, opts = {})
      chain = [input]

      if dynamic?
        full_model = build_model(model, opts)

        name = self.class.name.underscore
        full_model[name] = {}
        serialize_model!(self.class.name.underscore, full_model,
          opts.merge(:skip_transforms => true))
      end

      if !transforms.blank?
        liquid_flags = template.liquid_flags(full_model, opts)

        transforms.each do |t|
          last = chain[-1]
          name = t[NAME]
          next if name.blank?

          transform_class = self.class.transform_class(name)
          next if transform_class.nil?

          params = t.except(NAME).deep_symbolize_keys!
          transform = transform_class.new(params)

          chain.push(
            lambda { |&block|
              transform.transform_content(last, full_model,
                opts.merge(:liquid_flags => liquid_flags), &block) }
          )
        end
      end

      if block_given?
        chain[-1].call { |c| yield c }
      else
        result = ''
        chain[-1].call { |c| result << c }
        result
      end
    end

    def transform_model!(name, model, opts)
      return if transforms.blank?

      transforms.each do |t|
        transform_name = t[NAME]
        next if transform_name.blank?

        transform_class = self.class.transform_class(transform_name)
        next if transform_class.nil?

        params = t.except(NAME).symbolize_keys!
        transform = transform_class.new(params)

        transform.transform_model!(name, model, opts)
      end
    end

    def extract_content_type(value)
      value.split(';'.freeze)[0].strip
    end

    def transforms_check
      if !transforms.nil?
        errors.add(:transforms,
          'transforms attribute must be an array') if !transforms.is_a?(Array)
      end
    end

    Resource.register_transform(Pompa::ResourceTransforms::Pipe)
    Resource.register_transform(Pompa::ResourceTransforms::Zip)
    Resource.register_transform(Pompa::ResourceTransforms::Replace)
end
