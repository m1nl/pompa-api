require 'liquid'
require 'base64'

module Pompa
  module LiquidExtensions
    module Base64Filter
      def base64_encode(input, urlsafe = false)
          if urlsafe
            Base64.urlsafe_encode64(input, padding: false)
          else
            Base64.strict_encode64(input)
          end
        rescue StandardError => e
          raise Liquid::ArgumentError.new(e.message)
      end
    
      def base64_decode(input, urlsafe = false)
          if urlsafe
            Base64.urlsafe_decode64(input)
          else
            Base64.strict_decode64(input)
          end
        rescue StandardError => e
          raise Liquid::ArgumentError.new(e.message)
      end
    end
  end
end

Liquid::Template.register_filter(Pompa::LiquidExtensions::Base64Filter)
