require 'liquid'
require 'addressable'

class Template < ApplicationRecord
  include Pageable
  include LiquidTemplate
  include Model
  include NullifyBlanks

  CID_URI = 'cid:%s'.freeze
  TRACKING_TAG = '<img src="%s" alt="" width="1" height="1" />'.freeze

  SENDER_EMAIL = 'sender_email'.freeze
  SENDER_NAME = 'sender_name'.freeze
  BASE_URL = 'base_url'.freeze
  LANDING_URL = 'landing_url'.freeze
  SUBJECT = 'subject'.freeze
  PLAINTEXT = 'plaintext'.freeze
  HTML = 'html'.freeze
  FILENAME = 'filename'.freeze
  SUFFIX = 'suffix'.freeze
  LOCATION = 'location'.freeze

  has_many :goals
  has_many :resources
  has_many :attachments
  has_many :scenarios

  validates :name, presence: true
  validates :base_url, :url => { :allow_nil => true, :allow_blank => true }

  nullify_blanks :sender_email, :sender_name, :base_url, :landing_url,
    :report_url, :static_resource_url, :dynamic_resource_url

  liquid_template :report_url, default: Rails.configuration
      .pompa.template.report_url
  liquid_template :static_resource_url, default: Rails.configuration
      .pompa.template.static_resource_url
  liquid_template :dynamic_resource_url, default: Rails.configuration
      .pompa.template.dynamic_resource_url

  liquid_template :sender_email
  liquid_template :sender_name
  liquid_template :landing_url
  liquid_template :subject
  liquid_template :plaintext
  liquid_template :html

  def liquid_flags(model = {}, opts = {})
    full_model = build_model(model, opts)
    filters = TemplateFilters.new(self, full_model, opts)
    return { :filters => [filters] }.merge!(Pompa::Utils.liquid_flags)
  end

  def serialize_model!(name, model, opts)
    @default_base_url ||= Rails.configuration.pompa.template.base_url

    model[name].merge!(
      TemplateSerializer.new(self)
        .serializable_hash(:include => []).except!(*[:landing_url,
        :report_url, :static_resource_url, :dynamic_resource_url,
        :subject, :plaintext, :html, :links]).deep_stringify_keys
    )

    model[name][BASE_URL] = @default_base_url if model.dig(name, BASE_URL)
      .blank?

    flags = liquid_flags(model, opts)

    model[name].merge!(
        { SENDER_EMAIL => sender_email_template.render!(model, flags) }
    )
    model[name].merge!(
        { SENDER_NAME => sender_name_template.render!(model, flags) }
    )
    model[name].merge!(
        { LANDING_URL => landing_url_template.render!(model, flags) }
    )
    model[name].merge!(
        { SUBJECT => subject_template.render!(model, flags) }
    )
    model[name].merge!(
        {
          PLAINTEXT => plaintext_template.render!(model, flags),
          HTML => html_template.render!(model, flags),
        }
    )
  end

  def duplicate
    copy = dup
    copy.name = "#{copy.name} (copy)" while Template.exists?(
      :name => copy.name)

    ActiveRecord::Base.transaction do
      copy.save!

      goals
        .each { |g| g.dup.tap { |o| o.template_id = copy.id }.save! }
      resources.with_attached_file
        .each { |r| r.dup.tap { |o| o.template_id = copy.id }.save! }

      attachments.each do |a|
        a = a.dup.tap { |o| o.template_id = copy.id }
        a.resource_id = copy.resources.where(
          :name => a.resource.name).pick(:id)
        a.save!
      end
    end

    return copy
  end

  def export
    Worker.reply_queue_key_name.tap { |q|
      TemplateExportJob.perform_later(:template_id => id, :reply_to => q)
    }
  end

  class << self
    def import(zip_path)
      Worker.reply_queue_key_name.tap { |q|
        TemplateImportJob.perform_later(:zip_path => zip_path, :reply_to => q)
      }
    end
  end

  private
    class TemplateFilters < Module
      def initialize(template, model, opts = {})
        super() do
          define_method :resource do |input, suffix = nil, filename = nil|
            @template ||= template
            @model ||= model
            @opts ||= opts

            @resources ||= @template.resources
            raise Liquid::ArgumentError,
              'unable to access resources' if @resources.nil?

            resource_id = @resources.where(name: input)
              .pick(:id)
            raise Liquid::ArgumentError,
              "resource \"#{input}\" not found" if resource_id.nil?

            full_model = Resource.build_model(resource_id,
              @model, @opts)
            full_model[SUFFIX] = suffix || ''
            full_model[FILENAME] = filename || ''

            if !!full_model.dig('resource', 'dynamic')
              return @template.dynamic_resource_url_template
                .render!(full_model, Pompa::Utils.liquid_flags)
            else
              return @template.static_resource_url_template
                .render!(full_model, Pompa::Utils.liquid_flags)
            end
          end

          define_method :render do |input|
            @template ||= template
            @model ||= model
            @opts ||= opts

            @resources ||= @template.resources
            raise Liquid::ArgumentError,
              'unable to access resources' if @resources.nil?

            resource = @resources.where(name: input).first
            raise Liquid::ArgumentError,
              "resource \"#{input}\" not found" if resource.nil?

            return resource.render(@model, @opts)
          end

          define_method :embed do |input|
            @template ||= template
            @model ||= model
            @opts ||= opts

            @resources ||= @template.resources
            raise Liquid::ArgumentError,
              'unable to access resources' if @resources.nil?

            resource_id = @resources.where(name: input)
              .pick(:id)
            raise Liquid::ArgumentError,
              "resource \"#{input}\" not found" if resource_id.nil?

            full_model = Resource.build_model(resource_id,
              @model, @opts)

            CID_URI % full_model.dig('resource', 'code')
          end

          define_method :report do |input, location = nil|
            @template ||= template
            @model ||= model
            @opts ||= opts

            @goals ||= @template.goals
            raise Liquid::ArgumentError,
              'unable to access goals' if @goals.nil?

            goal_id = @goals.where(name: input)
              .pick(:id)
            raise Liquid::ArgumentError,
              "goal \"#{input}\" not found" if goal_id.nil?

            full_model = Goal.build_model(goal_id, @model, @opts)
            full_model[LOCATION] = location || ''
            return @template.report_url_template
              .render!(full_model, Pompa::Utils.liquid_flags)
          end

          define_method :track do |input|
            TRACKING_TAG % report(input)
          end
        end
      end
    end
end
