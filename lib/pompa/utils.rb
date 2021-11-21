require 'securerandom'
require 'digest'
require 'base64'
require 'zlib'
require 'rbnacl'
require 'i18n'
require 'uri'
require 'jwt'

module Pompa
  class Utils
    class << self
      DEFAULT_TRUNCATE = 50

      JWT_ALGORITHM = 'ED25519'.freeze

      def random_code
        SecureRandom.urlsafe_base64(code_length)
      end

      def short_uuid
        SecureRandom.uuid.gsub!('-', '')
      end

      def uuid
        SecureRandom.uuid
      end

      def urlsafe_digest(value)
        sha1 = Digest::SHA1.new
        sha1 << value
        Base64.urlsafe_encode64(sha1.digest, padding: false)[0, code_length]
      end

      def code_length
        @code_length ||= Rails.configuration.pompa.code_length
      end

      def liquid_flags
        { strict_variables: true, strict_filters: true }
      end

      def shared_tmpdir
        return @shared_tmpdir if !@shared_tmpdir.blank?

        [ENV['SHARED_TMPDIR'], ENV['SHARED_TMP'], ENV['SHARED_TEMP']].each do |d|
          next if d.blank?

          d = File.expand_path(d)
          if stat = File.stat(d) and stat.directory? and stat.writable? and
            (!stat.world_writable? or stat.sticky?)
            @shared_tmpdir = d
            break
          end rescue nil
        end

        @shared_tmpdir = Dir.tmpdir if @shared_tmpdir.blank?
        @shared_tmpdir
      end

      def truncate(value)
        if value.is_a?(Hash)
          value.transform_values { |x| truncate(x) }
        elsif value.is_a?(Array)
          value.map { |x| truncate(x) }
        elsif value.is_a?(String)
          value.truncate(DEFAULT_TRUNCATE)
        else
          value
        end
      end

      def permit_raw(params, tap, param)
        if params[param].respond_to?(:to_unsafe_h)
          tap[param] = params[param].to_unsafe_h
        elsif params[param].respond_to?(:map)
          tap[param] = params[param].map { |p|
            p.to_unsafe_h if p.respond_to?(:to_unsafe_h)
          }
        elsif params[param].nil?
          tap[param] = nil
        else
          tap[param] = params[param]
        end
      end

      def sanitize_filename(filename)
        bad_chars = ['/', '\\', '?', '%', '*', ':', '|',
          '"', '<', '>']
        bad_chars.each do |bad_char|
          filename.gsub!(bad_char, '_')
        end
        filename
      end

      def content_disposition(filename)
         transliterated_filename = I18n.transliterate(filename)
         sanitized_filename = sanitize_filename(transliterated_filename)

         result = "attachment; filename=\"#{sanitized_filename}\""

         if !filename.ascii_only?
           encoded_filename = URI.encode(filename.encode(Encoding::UTF_8))
           result += "; filename*=UTF-8''#{encoded_filename}"
         end

         return result
      end

      def encrypt(input, compress = false)
        input = Zlib::Deflate.new.deflate(input, Zlib::FINISH) if compress

        encrypted = secret_box.encrypt(input)
        return Base64.urlsafe_encode64(encrypted, padding: false)
      end

      def decrypt(input, decompress = false)
        decoded = Base64.urlsafe_decode64(input)

        plaintext = secret_box.decrypt(decoded)
        return decompress ? Zlib::Inflate.new.inflate(plaintext) : plaintext
      end

      def sign(input, compress = false)
        input = Zlib::Deflate.new.deflate(input, Zlib::FINISH) if compress

        signed = signing_key.sign(input)
        return Base64.urlsafe_encode64(signed, padding: false)
      end

      def signed_token(data)
        payload = data.merge({ iat: Time.now.to_i })

        return JWT.encode(payload, signing_key, JWT_ALGORITHM)
      end

      def verify_key_bytes(encode = true)
        bytes = signing_key.verify_key.to_s

        if encode
          return Base64.urlsafe_encode64(bytes, padding: false)
        else
          return bytes
        end
      end

      private
        def encryption_key_seed
          @encryption_key_seed ||= Rails.application.key_generator.generate_key('',
            RbNaCl::SecretBox.key_bytes)
        end

        def signing_key_seed
          @signing_key_seed ||= Rails.application.key_generator.generate_key('',
            RbNaCl::Signatures::Ed25519::SEEDBYTES)
        end

        def signing_key
          return RbNaCl::SigningKey.new(signing_key_seed)
        end

        def secret_box
          return RbNaCl::SimpleBox::from_secret_key(encryption_key_seed)
        end
    end
  end
end
