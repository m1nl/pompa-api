module Pompa
  module ResourceTransforms
    class Pipe
      def initialize(params = {})
        @params = params
      end

      def transform_content(input, model, opts)
        input.call { |c| yield c }
      end

      def transform_model!(name, model, opts)
      end
    end
  end
end
