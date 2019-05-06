require 'tmpdir'
require 'json'
require 'digest'

class TemplateImportJob < ApplicationJob
  include Pompa::Worker

  RESOURCE = 'resource'.freeze

  TEMPLATE_FILENAME = 'template.json'.freeze
  GOALS_FILENAME = 'goals.json'.freeze
  RESOURCES_FILENAME = 'resources.json'.freeze
  ATTACHMENTS_FILENAME = 'attachments.json'.freeze

  def instance_id
    self.job_id
  end

  class << self
    def cleanup(opts)
      Pompa::RedisConnection.redis(opts) do |r|
        zip_path = r.get(zip_path_key_name(opts[:instance_id]))
        keep_file = !!r.get(keep_file_key_name(opts[:instance_id]))
        File.delete(zip_path) if !keep_file && !zip_path.blank? &&
          File.file?(zip_path)

        r.del(zip_path_key_name(opts[:instance_id]))
        r.del(keep_file_key_name(opts[:instance_id]))
      end
    end

    def zip_path_key_name(instance_id)
      "#{name}:#{instance_id}:zip_path"
    end

    def keep_file_key_name(instance_id)
      "#{name}:#{instance_id}:keep_file"
    end
  end

  protected
    def invoke(opts = {})
      super(opts)

      self.zip_path = opts.delete(:zip_path)
      self.keep_file = !!opts.delete(:keep_file)

      return result(INVALID) if zip_path.blank? || !File.file?(zip_path)

      template = nil

      ActiveRecord::Base.transaction do
        Zip::File.open(zip_path) do |zip_file|
          entry = zip_file.find_entry(TEMPLATE_FILENAME)
          json = entry.get_input_stream.read
          hash = JSON.parse(json).deep_symbolize_keys!

          template = Template.new(
            hash.slice(*Template.column_names.map(&:to_sym)))
          template.name = "#{template.name} (imported)" while Template.exists?(
            :name => template.name)
          template.save!

          entry = zip_file.find_entry(GOALS_FILENAME)
          json = entry.get_input_stream.read
          hash_array = JSON.parse(json)

          hash_array.each do |g|
            goal = Goal.new(g.deep_symbolize_keys!.slice(
              *Goal.column_names.map(&:to_sym) - [:template_id]))
            goal.template_id = template.id
            goal.save!
          end

          entry = zip_file.find_entry(RESOURCES_FILENAME)
          json = entry.get_input_stream.read
          hash_array = JSON.parse(json)

          hash_array.each do |r|
            resource = Resource.new(r.deep_symbolize_keys!.slice(
              *Resource.column_names.map(&:to_sym) - [:template_id]))
            resource.template_id = template.id

            filename = "#{RESOURCE}-#{Digest::SHA1.hexdigest(resource.name)}"
            entry = zip_file.find_entry(filename)

            if !entry.nil? && !r[:file].nil?
              temp_filename = Dir::Tmpname.create([RESOURCE]) { }

              begin
                entry.extract(temp_filename)
                resource.file.attach({
                  io: File.open(temp_filename, 'rb'),
                  filename: r.dig(:file, :filename),
                  content_type: r.dig(:file, :content_type)
                })
                mark
              ensure
                File.delete(temp_filename) if File.file?(temp_filename)
              end
            end

            resource.save!
          end

          entry = zip_file.find_entry(ATTACHMENTS_FILENAME)
          json = entry.get_input_stream.read
          hash_array = JSON.parse(json)

          hash_array.each do |a|
            attachment = Attachment.new(a.deep_symbolize_keys!.slice(
              *Attachment.column_names.map(&:to_sym) - [:template_id,
              :resource_id]))
            attachment.template_id = template.id
            attachment.resource_id = template.resources.where(
              :name => a[:resource_name]).pluck(:id).first
            attachment.save!
          end
        end
      end

      File.delete(zip_path) if !keep_file && File.file?(zip_path)

      mark

      return result(SUCCESS, template.id) if !template.nil?
      return result(FAILED)
    end

    def tick
      true
    end

    def finished?
      true
    end

    ###

    def zip_path
      redis.with { |r| r.get(zip_path_key_name) }
    end

    def zip_path=(value)
      redis.with { |r| r.set(zip_path_key_name, value) }
    end

    def keep_file
      redis.with { |r| r.get(keep_file_key_name) }
    end

    def keep_file=(value)
      redis.with { |r| r.set(keep_file_key_name, value) }
    end

    ###

    def zip_path_key_name
      self.class.zip_path_key_name(instance_id)
    end

    def keep_file_key_name
      self.class.keep_file_key_name(instance_id)
    end
end
