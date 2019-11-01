require 'pompa/redis_connection'
require 'jwt'
require 'base64'

module Pompa
  module Authentication
    class Token
      class << self
        AUTH_TIMEOUT = 300.seconds
        AUTH_BYTES = 32

        JWT_ALGORITHM = 'ED25519'

        def preauthenticate(code, params = {})
          nonce = Base64.urlsafe_encode64(RbNaCl::Random.random_bytes(
            AUTH_BYTES), padding: false)

          payload = params.merge({ encrypted_nonce: Pompa::Utils.encrypt(nonce),
            authenticated: false, exp: AUTH_TIMEOUT.from_now.to_i })
          token = JWT.encode(payload, signing_key, JWT_ALGORITHM)

          redis.with do |r|
            r.setex(auth_nonce_key(code), AUTH_TIMEOUT, token)
          end

          return nonce
        end

        def authenticate(code, params = {})
          auth_nonce_key = auth_nonce_key(code)
          payload = nil

          redis.with do |r|
            r.watch(auth_nonce_key) do
              token = r.get(auth_nonce_key)
              raise AuthenticationError.new if token.nil?

              payload = nil

              begin
                payload = JWT.decode(token, verify_key, true,
                  { algorithm: JWT_ALGORITHM })
              rescue JWT::DecodeError
                raise AuthenticationError.new
              end

              raise AuthenticationError.new if payload.nil? ||
                !payload.kind_of?(Array)

              payload = payload[0]
              raise AuthenticationError.new if payload.blank? ||
                !payload.is_a?(Hash)

              payload.symbolize_keys!
              raise AuthenticationError.new if !!payload[:authenticated]

              payload = params.merge(payload)
              payload[:authenticated] = true

              token = JWT.encode(payload, signing_key, JWT_ALGORITHM)

              result = r.multi do |m|
                m.setex(auth_nonce_key, AUTH_TIMEOUT, token)
              end

              raise AuthenticationError.new if result.nil?
            end
          end

          return payload

          rescue AuthenticationError => e
            redis.with { |r| r.del(auth_nonce_key) }
            raise e
        end

        def validate(code, nonce)
          auth_nonce_key = auth_nonce_key(code)
          payload = nil

          redis.with do |r|
            r.watch(auth_nonce_key) do
              token = r.get(auth_nonce_key)
              raise ValidationError if token.blank?

              payload = nil

              begin
                payload = JWT.decode(token, verify_key, true,
                  { algorithm: JWT_ALGORITHM })
              rescue JWT::DecodeError
                raise ValidationError.new
              end

              raise ValidationError.new if payload.nil? ||
                !payload.kind_of?(Array)

              payload = payload[0]
              raise ValidationError.new if payload.blank? || !payload.is_a?(Hash)

              payload.symbolize_keys!
              raise ValidationError.new if !payload[:authenticated] ||
                Pompa::Utils.decrypt(payload[:encrypted_nonce]) != nonce

              result = r.multi do |m|
                m.del(auth_nonce_key)
              end

              raise ValidationError.new if result.nil?
            end
          end

          return payload

          rescue ValidationError => e
            redis.with { |r| r.del(auth_nonce_key) }
            raise e
        end

        def generate_token(client_id, params = {})
          payload = params.merge(client_id: client_id,
            exp: AUTH_TIMEOUT.from_now.to_i)
          return JWT.encode(payload, signing_key, JWT_ALGORITHM)
        end

        def parse_token(token)
          begin
            JWT.decode(token, verify_key, true,
              { algorithm: JWT_ALGORITHM })
          rescue JWT::DecodeError
            raise ValidationError.new
          end

          raise ValidationError.new if payload.nil? ||
            !payload.kind_of?(Array)

          payload = payload[0]
          raise ValidationError.new if payload.blank? || !payload.is_a?(Hash)

          return payload.symbolize_keys!
        end

        def refresh_token(token)
          payload = parse_token(token).merge!(exp: AUTH_TIMEOUT.from_now.to_i)
          return JWT.encode(payload, signing_key, JWT_ALGORITHM)
        end

        private
          def redis
            @redis ||= Pompa::RedisConnection.pool
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

          def auth_nonce_key(code)
            "AuthNonce:#{code}"
          end
      end
    end
  end
end
