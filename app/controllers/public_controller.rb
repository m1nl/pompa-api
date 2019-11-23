require 'base64'
require 'uri'

class PublicController < ApplicationController
  include ActionController::MimeResponds
  include ActionController::Cookies

  skip_authentication!

  rescue_from StandardError, :with => :handle_error if Rails.env.production?

  before_action :check_accept_header
  after_action :allow_iframe
  after_action :set_vary_header
  after_action :skip_authorization

  PNG_CONTENT_TYPE = 'image/png'.freeze
  JPEG_CONTENT_TYPE = 'image/jpeg'.freeze
  JPG_CONTENT_TYPE = 'image/jpg'.freeze
  GIF_CONTENT_TYPE = 'image/gif'.freeze

  IMAGE_CONTENT_TYPE = 'image/*'.freeze

  PNG_FORMAT = :png
  JPG_FORMAT = :jpg
  GIF_FORMAT = :gif

  ACCEPT_HEADER = 'Accept'.freeze
  CONTENT_TYPE_HEADER = 'Content-Type'.freeze
  LAST_MODIFIED_HEADER = 'Last-Modified'.freeze
  X_FRAME_OPTIONS_HEADER = 'X-Frame-Options'.freeze
  VARY_HEADER = 'Vary'.freeze
  PRAGMA_HEADER = 'Pragma'.freeze
  EXPIRES_HEADER = 'Expires'.freeze
  CONTENT_DISPOSITION_HEADER = 'Content-Disposition'.freeze

  RESOURCE = 'resource'.freeze
  CONTENT_TYPE = 'content_type'.freeze

  USER_AGENT = 'user-agent'.freeze
  IP = 'ip'.freeze
  REFERER = 'referer'.freeze
  METHOD = 'method'.freeze
  COOKIE = 'cookie'.freeze

  NO_STORE = 'no-store'.freeze
  MUST_REVALIDATE = 'must-revalidate'.freeze
  NO_CACHE = 'no-cache'.freeze
  ZERO = '0'.freeze
  FORCE_CACHE_EXTRAS = [NO_STORE, MUST_REVALIDATE].freeze

  TIMESTAMP = 'timestamp'.freeze
  CACHE_PATH = 'cache_path'.freeze

  IGNORE_PARAMS = [:v, :victim, :g, :goal, :t, :timestamp, :l, :location,
    :action, :controller, :format].freeze

  # ANY /public/
  def index
    return _report if [:goal, :g].any? { |p|
      params.has_key?(p) }
    return _render if request.get? && [:resource, :r].any? { |p|
      params.has_key?(p) }
    return head :not_found
  end

  def _report
    victim_code = params[:victim] || params[:v]
    goal_code = params[:goal] || params[:g]
    return head :not_found if victim_code.blank? || goal_code.blank?

    return head :not_found if Goal.template_id_by_code(goal_code) != Victim
      .template_id_by_code(victim_code)

    victim_id = Victim.id_by_code(victim_code)
    goal_id = Goal.id_by_code(goal_code)
    return head :not_found if victim_id.nil? || goal_id.nil?

    campaign_id = Victim.campaign_id_by_code(victim_code)
    return head :not_found if campaign_id.nil?

    location = params[:location] || params[:l]
    location = Pompa::Utils.decrypt(location, true)
      .force_encoding(Encoding::UTF_8) if !location.blank?

    @cookie_name ||= Rails.configuration.pompa.report.cookie_name
    cookies.permanent.signed[@cookie_name] ||= Pompa::Utils.random_code

    data = params.to_unsafe_h.except(*IGNORE_PARAMS).stringify_keys!
    data.merge!({ USER_AGENT => request.user_agent, IP => request.remote_ip,
      REFERER => request.referer, METHOD => request.method,
      COOKIE => cookies.permanent.signed[@cookie_name] })

    Campaign.push_event(campaign_id, victim_id, goal_id, data)

    force_expire

    if !location.blank? && location =~ URI::regexp
      redirect_to location, status: :see_other
    else
      respond_to do |f|
        f.html { render :ok, :body => '' }
        f.png do
          response.headers[CONTENT_TYPE_HEADER] = PNG_CONTENT_TYPE
          render :ok, :body => blank_png
        end
        f.jpg do
          response.headers[CONTENT_TYPE_HEADER] = JPG_CONTENT_TYPE
          render :ok, :body => blank_jpg
        end
        f.jpeg do
          response.headers[CONTENT_TYPE_HEADER] = JPEG_CONTENT_TYPE
          render :ok, :body => blank_jpg
        end
        f.gif do
          response.headers[CONTENT_TYPE_HEADER] = GIF_CONTENT_TYPE
          render :ok, :body => blank_gif
        end
      end
    end
  end

  def _render
    victim_code = params[:victim] || params[:v]
    timestamp = params[:timestamp] || params[:t]

    resource_code = params[:resource] || params[:r]
    return head :not_found if resource_code.blank?

    resource_id = Resource.id_by_code(resource_code)
    return head :not_found if resource_id.nil?

    unless timestamp.nil?
      cached_key_digest = Pompa::Utils.urlsafe_digest(
        Resource.cached_key(resource_id)
      )

      safe_params = params.permit(:resource, :r, :victim, :v, :timestamp, :t,
        :f, :filename)
      return redirect_to(url_for(safe_params
        .except(:timestamp, :t).merge(t: cached_key_digest, only_path: true)),
        status: :moved_permanently) if timestamp != cached_key_digest
    end

    resource = Resource.find_by_id(resource_id)
    return head :not_found if resource.nil?

    filename = params[:filename] || params[:f]
    filename = Pompa::Utils.decrypt(filename, false)
      .force_encoding(Encoding::UTF_8) if !filename.blank?

    model = {}

    if cache_enabled?
      expires_in(cache_expire, public: false,
        must_revalidate: true)
    else
      force_expire
    end

    if resource.static?
      return unless !cache_enabled? || stale?(etag: resource,
        last_modified: resource.updated_at, public: true)

      resource.build_model!(model, :shallow => true)
    else
      return head :not_found if victim_code.blank?

      return head :not_found if Victim
        .template_id_by_code(victim_code) != resource.template_id

      victim_id = Victim.id_by_code(victim_code)
      return head :not_found if victim_id.nil?

      Victim.build_model!(victim_id, model)
      resource.build_model!(model)

      return unless !cache_enabled? || stale?(etag: model[CACHE_PATH],
        last_modified: model[TIMESTAMP])
    end

    response.headers[CONTENT_TYPE_HEADER] = model.dig(RESOURCE,
      CONTENT_TYPE)
    response.headers[CONTENT_DISPOSITION_HEADER] =
      Pompa::Utils.content_disposition(filename) if !filename.blank?
    response.headers[LAST_MODIFIED_HEADER] ||= Time.current.httpdate

    self.status = :ok
    self.response_body = Resource::ContentWrapper.new(resource,
      :model => model, :render => true,
      :error_handler => method(:handle_streaming_error))
  end

  # ANY /public/*
  def not_found
    head :not_found
  end

  private
    def blank_png
      @blank_png ||= Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAA' +
        'CQd1PeAAAADElEQVQI12P4//8/AAX+Av7czFnnAAAAAElFTkSuQmCC').freeze
    end

    def blank_jpg
      @blank_jpg ||= Base64.decode64('/9j/2wBDAAEBAQEBAQEBAQEBAQEBAQEBAQEBAQ' +
        'EBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQH/2wBDAQEBA' +
        'QEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB' +
        'AQEBAQEBAQEBAQH/wgARCAABAAEDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAA' +
        'ACf/EABQBAQAAAAAAAAAAAAAAAAAAAAD/2gAMAwEAAhADEAAAAX8P/8QAFBABAAAAAA' +
        'AAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBA' +
        'wEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAA' +
        'AAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQA' +
        'BPyF//9oADAMBAAIAAwAAABAf/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPx' +
        'B//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPxB//8QAFBABAAAAAAAAAAAAA' +
        'AAAAAAAAP/aAAgBAQABPxB//9k=').freeze
    end

    def blank_gif
      @blank_gif ||= Base64.decode64('R0lGODdhAQABAIAAAP///////ywAAAAAAQABAA' +
        'ACAkQBADs=').freeze
    end

    def check_accept_header
      accept = request.headers[ACCEPT_HEADER]
      return if accept.blank?

      return request.format = PNG_FORMAT if accept.include?(PNG_CONTENT_TYPE)
      return request.format = JPG_FORMAT if accept.include?(JPEG_CONTENT_TYPE)
      return request.format = JPG_FORMAT if accept.include?(JPG_CONTENT_TYPE)
      return request.format = GIF_FORMAT if accept.include?(GIF_CONTENT_TYPE)
      return request.format = PNG_FORMAT if accept.include?(IMAGE_CONTENT_TYPE)
    end

    def allow_iframe
      response.headers.except!(X_FRAME_OPTIONS_HEADER)
    end

    def set_vary_header
      vary_header = response.headers[VARY_HEADER]
      vary_header ||= ''

      items = vary_header.split(',').map(&:strip)
      items.push(ACCEPT_HEADER)

      response.headers[VARY_HEADER] = items.join(', ')
    end

    def force_expire
      response.cache_control.replace(no_cache: true)
      response.cache_control[:extras] = FORCE_CACHE_EXTRAS

      response.headers[PRAGMA_HEADER] = NO_CACHE
      response.headers[EXPIRES_HEADER] = ZERO
    end

    def handle_error(e)
      multi_logger.error{"Error in #{self.class.name}, #{e.class}: #{e.message}"}
      multi_logger.backtrace(e)

      head :not_found
    end

    def handle_streaming_error(e)
      error_message = "Error in #{self.class.name}, #{e.class}: #{e.message}"

      multi_logger.error(error_message)
      multi_logger.backtrace(e)

      "<!-- #{error_message} -->"
    end

    private
      def cache_expire
        @cache_expire ||= Rails.configuration.pompa
          .response_cache.expire.seconds
      end

      def cache_enabled?
        @cache_enabled = Rails.configuration.pompa
          .response_cache.enable if @cache_enabled.nil?
        @cache_enabled
      end
end
