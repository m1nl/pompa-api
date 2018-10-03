module Pompa
  module ResourceTransforms
    class Replace
      def initialize(params = {})
        @params = params
        @from_template = Liquid::Template.parse(
          params[:from] || '')
        @to_template = Liquid::Template.parse(
          params[:to] || '')
        @fill = params[:fill] || ''
      end

      def transform_content(input, model, opts)
        from = @from_template.render!(
          model, opts[:liquid_flags])
        to = @to_template.render!(
          model, opts[:liquid_flags])

        stream = ''
        input.call { |c| stream << c }

        if !from.blank? && !to.blank?
          to = to.ljust(from.length, @fill) if !@fill.blank?
          stream.gsub!(from, to)
        end

        yield stream
      end

      def transform_model!(name, model, opts)
      end
    end
  end
end
