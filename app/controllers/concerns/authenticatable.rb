module Authenticatable
  extend ActiveSupport::Concern

  included do
    extend AuthenticatableClassMethods

    before_action :authenticate
  end

  def bearer_token
    pattern = /^Bearer /
    header  = request.headers['Authorization']
    header.gsub(pattern, '') if header && header.match(pattern)
  end

  def authentication_token
    @authentication_token
  end

  def authenticated_client_id
    authentication_token[:authenticated_client_id]
  end  

  private
    def authenticate
      @authentication_token = {}

      return true if skip_authentication
      return true if skip_authentication_for.include?(action_name.to_sym)

      token = bearer_token
      return head :unauthorized if token.blank?

      begin
        payload = Pompa::Authentication::Token.parse_token(token)
      rescue Pompa::Authentication::ValidationError
        return head :unauthorized
      end

      @authentication_token = payload
    end

    def skip_authentication
      self.class.skip_authentication
    end

    def skip_authentication_for
      self.class.skip_authentication_for
    end

    module AuthenticatableClassMethods
      def skip_authentication
        return !!@skip_authentication
      end

      def skip_authentication=(value)
        @skip_authentication = !!value
      end

      def skip_authentication_for(*actions)
        @skip_authentication_for ||= []
        return @skip_authentication_for if actions.nil? || actions.empty?
 
        @skip_authentication_for.push(*actions)
      end
    end
end
