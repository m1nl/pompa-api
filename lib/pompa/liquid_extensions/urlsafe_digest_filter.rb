require 'base64'

module Pompa
  module LiquidExtensions
    module UrlSafeDigestFilter
      def urlsafe_digest(input)
          Pompa::Utils.urlsafe_digest(input)
        rescue StandardError => e
          raise Liquid::ArgumentError.new(e.message)
      end
    end
  end
end

Liquid::Template.register_filter(Pompa::LiquidExtensions::UrlSafeDigestFilter)
