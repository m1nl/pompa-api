require 'base64'
require 'zlib'
require 'openssl'

module Pompa
  module LiquidExtensions
    module EncryptionFilter
      def encrypt(input, compress = false)
          Pompa::Utils.encrypt(input, compress)
        rescue StandardError => e
          raise Liquid::ArgumentError.new(e.message)
      end

      def decrypt(input, decompress = false)
          Pompa::Utils.decrypt(input, decompress)
        rescue StandardError => e
          raise Liquid::ArgumentError.new(e.message)
      end
    end
  end
end

Liquid::Template.register_filter(Pompa::LiquidExtensions::EncryptionFilter)
