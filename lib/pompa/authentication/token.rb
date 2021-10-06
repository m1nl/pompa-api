require 'pompa/redis_connection'
require 'jwt'
require 'base64'

module Pompa
  module Authentication
    class Token
      class << self
        AUTH_BYTES = 32
        TIME_SHIFT = 10.seconds

        JWT_ALGORITHM = 'ED25519'.freeze
        JWT_ACCESS_AUD = 'access_token@pompa'.freeze
        JWT_AUTHENTICATE_AUD = 'authentication_token@pompa'.freeze
        JWT_TEMPORARY_ACCESS_AUD = 'temporary_access_token@pompa'.freeze

        JWT_TYPE_AUD_MAPPING = { :any => [JWT_ACCESS_AUD, JWT_TEMPORARY_ACCESS_AUD],
          :access => [JWT_ACCESS_AUD], :temporary => [JWT_TEMPORARY_ACCESS_AUD] }

        def preauthenticate(code, params = {})
          nonce = Base64.urlsafe_encode64(RbNaCl::Random.random_bytes(
            AUTH_BYTES), padding: false)
          encrypted_nonce = Pompa::Utils.encrypt(nonce)

          payload = params.merge({ aud: JWT_AUTHENTICATE_AUD,
            sub: "#{code}@pompa", enc_nonce: encrypted_nonce,
            iat: Time.now.to_i, exp: authentication_timeout.from_now.to_i,
            jti: Pompa::Utils.short_uuid })
          token = JWT.encode(payload, signing_key, JWT_ALGORITHM)

          redis.with do |r|
            r.setex(auth_token_key(code),
              (authentication_timeout + TIME_SHIFT).to_i, token)
          end

          return nonce
        end

        def introspect(code)
          auth_token_key = auth_token_key(code)
          payload = nil

          redis.with do |r|
            r.watch(auth_token_key) do
              token = r.get(auth_token_key)
              raise(AuthenticationError,
                'Authentication token not found') if token.blank?

              payload = nil

              begin
                payload = JWT.decode(token, verify_key, true,
                  { algorithm: JWT_ALGORITHM, verify_iat: true,
                    verify_aud: true, aud: JWT_AUTHENTICATE_AUD,
                    verify_sub: true, sub: "#{code}@pompa" })
              rescue JWT::DecodeError => e
                raise(AuthenticationError, "JWT parse error: #{e.message}")
              end

              raise(AuthenticationError,
                'JWT parse error: payload is not an array') if payload.nil? ||
                  !payload.kind_of?(Array)

              payload = payload[0]
              raise(AuthenticationError,
                'JWT parse error: inner payload is not a hash') if payload.blank? ||
                  !payload.is_a?(Hash)

              payload.symbolize_keys!

              yield payload if block_given?
            end
          end

          return payload

          rescue AuthenticationError => e
            redis.with { |r| r.del(auth_token_key) }
            raise e
        end

        def authenticate(code, params = {})
          auth_token_key = auth_token_key(code)
          payload = nil

          redis.with do |r|
            r.watch(auth_token_key) do
              token = r.get(auth_token_key)
              raise(AuthenticationError,
                'Authentication token not found') if token.blank?

              payload = nil

              begin
                payload = JWT.decode(token, verify_key, true,
                  { algorithm: JWT_ALGORITHM, verify_iat: true,
                    verify_aud: true, aud: JWT_AUTHENTICATE_AUD,
                    verify_sub: true, sub: "#{code}@pompa" })
              rescue JWT::DecodeError => e
                raise(AuthenticationError, "JWT parse error: #{e.message}")
              end

              raise(AuthenticationError,
                'JWT parse error: payload is not an array') if payload.nil? ||
                  !payload.kind_of?(Array)

              payload = payload[0]
              raise(AuthenticationError,
                'JWT parse error: inner payload is not a hash') if payload.blank? ||
                  !payload.is_a?(Hash)

              payload.symbolize_keys!
              raise(AuthenticationError,
                'Token already authenticated') if !!payload[:authenticated]

              payload = params.merge(payload)
              payload[:authenticated] = true

              token = JWT.encode(payload, signing_key, JWT_ALGORITHM)

              result = r.multi do |m|
                m.setex(auth_token_key,
                  (authentication_timeout + TIME_SHIFT).to_i, token)
              end

              raise(AuthenticationError,
                'Token already updated, transaction failed') if result.nil?
            end
          end

          return payload

          rescue AuthenticationError => e
            redis.with { |r| r.del(auth_token_key) }
            raise e
        end

        def validate(code, nonce)
          auth_token_key = auth_token_key(code)
          payload = nil

          redis.with do |r|
            r.watch(auth_token_key) do
              token = r.get(auth_token_key)
              raise(AuthenticationError,
                'Authentication token not found') if token.blank?

              payload = nil

              begin
                payload = JWT.decode(token, verify_key, true,
                  { algorithm: JWT_ALGORITHM, verify_iat: true,
                    verify_aud: true, aud: JWT_AUTHENTICATE_AUD,
                    verify_sub: true, sub: "#{code}@pompa" })
              rescue JWT::DecodeError => e
                raise(AuthenticationError, "JWT parse error: #{e.message}")
              end

              raise(AuthenticationError,
                'JWT parse error: payload is not an array') if payload.nil? ||
                  !payload.kind_of?(Array)

              payload = payload[0]
              raise(AuthenticationError,
                'JWT parse error: inner payload is not a hash') if payload.blank? ||
                  !payload.is_a?(Hash)

              payload.symbolize_keys!
              raise(AuthenticationError,
                'Token not authenticated') if !payload[:authenticated]
              raise(AuthenticationError,
                'Nonce does not match') if Pompa::Utils
                  .decrypt(payload[:enc_nonce]) != nonce

              result = r.multi do |m|
                m.del(auth_token_key)
              end

              raise(AuthenticationError,
                'Token already validated, transaction failed') if result.nil?
            end
          end

          return payload

          rescue AuthenticationError => e
            redis.with { |r| r.del(auth_token_key) }
            raise e
        end

        ###

        def generate_token(client_id, params = {})
          temporary = !!params.delete(:temporary)
          scopes = params.delete(:scopes)

          aud = if temporary then JWT_TEMPORARY_ACCESS_AUD else JWT_ACCESS_AUD end
          timeout = if temporary then temporary_access_timeout else access_timeout end

          timestamp = Time.now
          payload = params.merge({ client_id: client_id, auth_time: timestamp.to_i,
              iat: timestamp.to_i, exp: timeout.since(timestamp).to_i,
              jti: Pompa::Utils.short_uuid, aud: aud })

          if !scopes.blank?
            payload.merge!({ scopes: Array(scopes) })
          end

          return JWT.encode(payload, signing_key, JWT_ALGORITHM)
        end

        def parse_token(token, opts = {})
          allowed_types = opts.delete(:allowed_types) || :access
          allow_revoked = !!opts.delete(:allow_revoked)

          allowed_auds = Array(allowed_types)
            .flat_map { |t| JWT_TYPE_AUD_MAPPING[t] }

          payload = nil

          begin
            decode_params = { algorithm: JWT_ALGORITHM, verify_iat: true,
              verify_jti: lambda { |jti| jti_valid?(jti, allow_revoked: allow_revoked) }}

            payload = JWT.decode(token, verify_key, true, decode_params)

            raise(AccessError,
              'JWT parse error: payload is not an array') if payload.nil? ||
                !payload.kind_of?(Array)

            payload = payload[0]
            raise(AccessError,
              'JWT parse error: inner payload is not a hash') if payload.blank? ||
                !payload.is_a?(Hash)

            payload.symbolize_keys!

            aud = payload[:aud]

            if aud.blank? || !allowed_auds.include?(aud) then
              raise(JWT::InvalidAudError,
                "Invalid audience. Expected #{allowed_auds.join(', ')}, received #{aud || '<none>'}")
            end
          rescue JWT::DecodeError => e
            raise(AccessError, "JWT parse error: #{e.message}")
          end

          return payload
        end

        def refresh_token(token)
          payload = parse_token(token)

          raise(ManipulationError,
           'Token cannot be refreshed') if payload[:auth_time].blank?

          diff = (Time.at(payload[:exp]) - Time.now).seconds
          raise(ManipulationError,
            'Token too fresh to be refreshed') if diff >= token_refresh_margin

          diff = (Time.now - Time.at(payload[:auth_time])).seconds
          raise(ManipulationError,
            'Authentication lifetime passed for this token') if diff >= authentication_lifetime

          payload.merge!({
            iat: Time.now.to_i, exp: access_timeout.from_now.to_i,
            jti: Pompa::Utils.short_uuid })
          return JWT.encode(payload, signing_key, JWT_ALGORITHM)
        end

        def revoke_token(token)
          payload = parse_token(token, allowed_types: :any)

          raise(ManipulationError,
            'Token already revoked') if jti_revoked?(payload[:jti])

          token_revoked_key = token_revoked_key(payload[:jti])

          redis.with do |r|
            r.multi do |m|
              m.set(token_revoked_key, 1)
              m.expireat(token_revoked_key, (payload[:exp] + TIME_SHIFT).to_i)
            end
          end
        end

        def token_revoked?(token)
          payload = parse_token(token, allowed_types: :any,
            allow_revoked: true)

          return jti_revoked?(payload.jti)
        end

        def jti_revoked?(jti)
          return false if jti.blank?

          redis.with do |r|
            return r.exists?(token_revoked_key(jti))
          end
        end

        def jti_valid?(jti, opts = {})
          allow_revoked = !!opts.delete(:allow_revoked)

          return false if jti.blank?
          return allow_revoked || !jti_revoked?(jti)
        end

        def authentication_timeout
          @authentication_timeout = Rails.configuration.pompa.authentication
            .authentication_timeout.seconds
        end

        def authentication_lifetime
          @authentication_lifetime = Rails.configuration.pompa.authentication
            .authentication_lifetime.seconds
        end

        def access_timeout
          @access_timeout = Rails.configuration.pompa.authentication
            .access_timeout.seconds
        end

        def temporary_access_timeout
          @access_timeout = Rails.configuration.pompa.authentication
            .temporary_access_timeout.seconds
        end

        def token_refresh_margin
          @access_timeout = Rails.configuration.pompa.authentication
            .token_refresh_margin.seconds
        end

        private
          def redis
            @redis ||= Pompa::RedisConnection.pool(
              :db => Pompa::RedisConnection::AUTH_DB)
          end

          ###

          def signing_key
            @signing_key = RbNaCl::SigningKey.new(signing_seed)
          end

          def verify_key
            signing_key.verify_key
          end

          def signing_seed
            @signing_seed ||= Rails.application.key_generator
              .generate_key('', AUTH_BYTES)
          end

          ###

          def auth_token_key(code)
            "AuthToken:#{code}"
          end

          def token_revoked_key(jti)
            "TokenRevoked:#{jti}"
          end
      end
    end
  end
end
