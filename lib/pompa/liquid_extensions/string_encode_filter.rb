require 'liquid'

module Pompa
  module LiquidExtensions
    module StringEncodeFilter
      def string_encode(input, encoding)
          input.encode(Encoding.find(encoding))
        rescue StandardError => e
          raise Liquid::ArgumentError.new(e.message)
      end
    
      def string_decode(input, encoding)
          input.force_encoding(encoding).encode(Encoding::UTF_8)
        rescue StandardError => e
          raise Liquid::ArgumentError.new(e.message)
      end
    end
  end
end

Liquid::Template.register_filter(Pompa::LiquidExtensions::StringEncodeFilter)
