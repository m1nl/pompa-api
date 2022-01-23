# frozen_string_literal: true

require "yaml"
require "active_support/ordered_options"
require "active_support/core_ext/object/inclusion"
require "active_support/core_ext/module/delegation"

module Pompa
  class Configuration < ActiveSupport::ConfigurationFile
    delegate :[], :fetch, to: :config
    delegate_missing_to :options

    def initialize(config_path)
      super(config_path)
    end

    def config
      @config ||= parse.deep_symbolize_keys
    end

    private
      def deep_transform(hash)
        return hash unless hash.is_a?(Hash)

        h = ActiveSupport::InheritableOptions.new
        hash.each do |k, v|
          h[k] = deep_transform(v)
        end
        h
      end

      def options
        @options ||= ActiveSupport::InheritableOptions.new(deep_transform(config))
      end
  end
end
