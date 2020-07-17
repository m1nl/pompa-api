require 'liquid'

module Pompa
  module LiquidExtensions
    module TransliterateFilter
      def transliterate(input)
          ActiveSupport::Inflector.transliterate(input)
        rescue StandardError => e
          raise Liquid::ArgumentError.new(e.message)
      end
    end
  end
end

Liquid::Template.register_filter(Pompa::LiquidExtensions::TransliterateFilter)
