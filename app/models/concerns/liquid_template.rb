require 'liquid'

module LiquidTemplate
  extend ActiveSupport::Concern

  included do
    after_save :reset_liquid_templates
    after_save :clear_liquid_templates_cache
  end

  def reload(opts = nil)
    reset_liquid_templates
    super(opts)
  end

  class_methods do
    def liquid_template(attribute, opts = {})
      liquid_template_attributes.push(attribute)

      define_method "#{attribute}_template" do |model = {}, opts = {}|
        cache_condition = self.class
          .liquid_templates_cache_conditions[attribute]
        defaults = self.class
          .liquid_templates_defaults[attribute]

        changed = "#{attribute}_changed?"
        perform_caching =
          ( cache_condition.nil? || self.instance_exec(&cache_condition) ) &&
          ( !self.respond_to?(changed) || !self.send(changed) )

        liquid_templates[attribute] ||=
          Pompa::Cache.fetch(liquid_template_cache_key(attribute),
            :condition => perform_caching) do
            num = self.method(attribute).arity

            args = [model, opts]
            args = args.first(num) if num >= 0

            template = self.send(attribute, *args)

            if template.blank? && !defaults.nil?
              template = defaults.respond_to?(:call) ? self
                .instance_exec(&defaults) : defaults
            end

            Liquid::Template.parse(template)
          end
      end

      if !opts[:readonly]
        define_method "#{attribute}=" do |value|
          liquid_templates[attribute] = nil
          super(value)
        end
      end

      if opts[:validate].nil? || !!opts[:validate]
        validates attribute, liquid_template: true
      end

      if !opts[:default].nil?
        liquid_templates_defaults[attribute] = opts[:default]
      end

      if !opts[:cache_condition].nil?
        liquid_templates_cache_conditions[attribute] = opts[:cache_condition]
      end
    end

    def liquid_template_attributes
      @liquid_template_attributes ||= []
    end

    def liquid_templates_defaults
      @liquid_templates_defaults ||= {}
    end

    def liquid_templates_cache_conditions
      @liquid_templates_cache_conditions ||= {}
    end
 end

  class LiquidTemplateValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      begin
        Liquid::Template.parse(value)
      rescue StandardError => e
        record.errors[attribute] << e.message
      end
    end
  end

  protected
    def liquid_templates
      @liquid_templates ||= {}
    end

    def reset_liquid_templates
      @liquid_templates = nil
    end

    def clear_liquid_templates_cache
      self.class.liquid_template_attributes.each do |a|
        Pompa::Cache.delete(liquid_template_cache_key(a))
      end
    end

    def liquid_template_cache_key(attribute)
      return nil if !persisted?

      "#{cache_key_with_version}/#{attribute}_template"
    end
end
