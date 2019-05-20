require 'liquid'
require 'base64'

module Pompa
  module LiquidExtensions
    module Base64Filter
      def base64_encode(input, urlsafe = false)
          if urlsafe
            Base64.urlsafe_encode64(input).gsub('=', '')
          else
            Base64.strict_encode64(input)
          end
        rescue StandardError => e
          raise Liquid::ArgumentError.new(e.message)
      end
    
      def base64_decode(input, urlsafe = false)
          Base64.decode64(urlsafe ? input.tr('-_', '+/') : input)
        rescue StandardError => e
          raise Liquid::ArgumentError.new(e.message)
      end
    end
  end
end

Liquid::Template.register_filter(Pompa::LiquidExtensions::Base64Filter)
