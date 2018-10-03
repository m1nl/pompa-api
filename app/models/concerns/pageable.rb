require 'active_support/concern'

module Pageable
  extend ActiveSupport::Concern

  class_methods do
    def paginate(opts)
      opts ||= {}
      opts[:number] ||= 1
      opts[:size] ||= Kaminari.config.default_per_page

      page(opts[:number]).per(opts[:size])
    end
  end
end
