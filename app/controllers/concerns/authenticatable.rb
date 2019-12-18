module Authenticatable
  extend ActiveSupport::Concern

  included do
    extend AuthenticatableClassMethods

    include ErrorHandlers
  end

  AUTHORIZATION = 'Authorization'.freeze
  BEARER_PATTERN = /^Bearer /.freeze
  TOKEN_PARAM = :_token

  def authentication_token
    @authentication_token
  end

  def authenticated_client_id
    return @authenticated_client_id if !@authenticated_client_id.blank?
    return nil if !authentication_token.is_a?(Hash)

    @authenticated_client_id = authentication_token[:client_id]
  end

  def current_user
    if authenticated_client_id.blank?
      @current_user = nil
      return nil
    end

    @current_user ||= User.where(client_id: authenticated_client_id).first

    if @current_user.nil? || @current_user.client_id != authenticated_client_id
      @current_user = nil
    end

    return @current_user
  end

  protected
    def authenticated_client_id=(value)
      @authenticated_client_id = value
    end

    def authenticate_url(url)
      return url if authenticated_client_id.blank? || url.blank?

      uri = Addressable::URI.parse(url)

      token = Pompa::Authentication::Token.generate_token(
        authenticated_client_id, temporary: true, scopes: [uri.path])

      query_values = uri.query_values || {}
      uri.query_values = query_values.merge(TOKEN_PARAM => token)
      return uri.to_s
    end

    def authenticate
      @authentication_token = {}
      @authenticated_client_id = nil

      return true if skip_authentication?
      return true if skip_authentication_for.include?(action_name.to_sym)

      token = bearer_token
      token_type = :access

      if token.blank?
        token = token_param
        return unauthorized_error if token.blank?

        token_type = :temporary
      end

      begin
        payload = Pompa::Authentication::Token.parse_token(token,
          allowed_types: token_type)
      rescue Pompa::Authentication::Error => e
        return unauthorized_error(e)
      end

      return forbidden_error if token_type == :temporary &&
        !allow_temporary_token_for.include?(action_name.to_sym)

      scopes = payload[:scopes]

      if !scopes.nil?
        scopes = Array(scopes)
        return forbidden_error if !scopes.include?(request.path)
      end

      @authentication_token = payload
    end

    def skip_authentication?
      self.class.skip_authentication?
    end

    def skip_authentication_for
      self.class.skip_authentication_for
    end

    def allow_temporary_token_for
      self.class.allow_temporary_token_for
    end

  private
    def bearer_token
      header = request.headers[AUTHORIZATION]

      return nil if header.blank? || !header.match(BEARER_PATTERN)
      return header.gsub(BEARER_PATTERN, '')
    end

    def token_param
      @token_param ||= params.extract!(TOKEN_PARAM).fetch(TOKEN_PARAM) {''}
    end


    def add_current_user_log_tag
      return yield if current_user.nil?

      logger.tagged(current_user.to_s) do
        yield
      end
    end

    module AuthenticatableClassMethods
      def skip_authentication?
        !!@skip_authentication
      end

      def skip_authentication!
        @skip_authentication = true
      end

      def skip_authentication_for(*actions)
        @skip_authentication_for ||= []
        return @skip_authentication_for if actions.nil? || actions.empty?

        @skip_authentication_for.push(*actions)
      end

      def allow_temporary_token_for(*actions)
        @allow_temporary_token_for ||= []
        return @allow_temporary_token_for if actions.nil? || actions.empty?

        @allow_temporary_token_for.push(*actions)
      end
    end
end
