require 'active_model_serializers'

module ActionController
  module Serialization
    def namespace_for_serializer
      @namespace_for_serializer ||= self.class.module_parent unless self.class.module_parent == Object
    end
  end
end
