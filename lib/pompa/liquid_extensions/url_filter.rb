require 'liquid'
require 'base64'
require 'addressable'

module Pompa
  module LiquidExtensions
    module UrlFilter
      def urlsafe_digest(input)
          Pompa::Utils.urlsafe_digest(input)
        rescue StandardError => e
          raise Liquid::ArgumentError.new(e.message)
      end

      def append_url(input, part)
        part ||= ''

        return input + part if input.is_a?(Addressable::URI)
        return Addressable::URI.parse(input) + part
      end
    end
  end
end

Liquid::Template.register_filter(Pompa::LiquidExtensions::UrlFilter)
