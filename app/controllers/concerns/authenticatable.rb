module Authenticatable
  extend ActiveSupport::Concern

  AUTHORIZATION = 'Authorization'.freeze
  BEARER_PATTERN = /^Bearer /.freeze

  included do
    extend AuthenticatableClassMethods

    before_action :authenticate
  end

  def authentication_token
    @authentication_token
  end

  def authenticated_client_id
    return @authenticated_client_id if !@authenticated_client_id.blank?
    return nil if !authentication_token.is_a?(Hash)

    @authenticated_client_id = authentication_token[:authenticated_client_id]
  end

  def authenticated_client_id=(value)
    @authenticated_client_id = value
  end

  def current_user
    if authenticated_client_id.blank?
      @current_user = nil
      return nil
    end

    @current_user ||= User.where(client_id: authenticated_client_id).first

    return @current_user if @current_user.client_id == authenticated_client_id

    @current_user = nil
    return current_user
  end

  private
    def bearer_token
      header = request.headers[AUTHORIZATION]

      return nil if header.blank? || !header.match(BEARER_PATTERN)
      return header.gsub(BEARER_PATTERN, '')
    end

    def authenticate
      @authentication_token = {}
      @authenticated_client_id = nil

      return true if skip_authentication?
      return true if skip_authentication_for.include?(action_name.to_sym)

      token = bearer_token
      return head :unauthorized if token.blank?

      begin
        payload = Pompa::Authentication::Token.parse_token(token)
      rescue Pompa::Authentication::AccessError
        return head :unauthorized
      end

      @authentication_token = payload
    end

    def skip_authentication?
      self.class.skip_authentication?
    end

    def skip_authentication_for
      self.class.skip_authentication_for
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
    end
end
