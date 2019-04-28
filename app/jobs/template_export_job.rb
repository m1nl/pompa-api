require 'tmpdir'
require 'json'
require 'digest'

class TemplateExportJob < ApplicationJob
  include Pompa::Worker

  TEMPLATE = 'template'.freeze
  RESOURCE = 'resource'.freeze
  ZIP = 'zip'.freeze

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
        File.delete(zip_path) if !zip_path.blank && File.file?(zip_path)

        r.del(zip_path_key_name(opts[:instance_id]))
      end
    end

    def zip_path_key_name(instance_id)
      "#{name}:#{instance_id}:zip_path"
    end
  end

  protected
    def invoke(opts = {})
      super(opts)

      template_id = opts.delete(:template_id)
      return result(INVALID) if template_id.nil?

      template = Template.find_by_id(template_id)
      return result(INVALID) if template.nil?

      return zip_file_response if !zip_path.blank? && File.file?(zip_path)

      self.zip_path = File.join(Dir.tmpdir,
        "#{TEMPLATE}-#{Pompa::Utils.uuid}.#{ZIP}")

      Dir.mktmpdir do |dir|
        input_filenames = []

        input_filenames << TEMPLATE_FILENAME

        File.open(File.join(dir, TEMPLATE_FILENAME), 'w') { |f|
          f.write(TemplateSerializer.new(template).serializable_hash(
            :include => []).except!(*[:id, :links]).to_json)
        }

        input_filenames << GOALS_FILENAME

        File.open(File.join(dir, GOALS_FILENAME), 'w') { |f|
          goals = []
          template.goals.each { |g| goals << GoalSerializer.new(g)
            .serializable_hash(:include => [])
            .except!(*[:id, :code, :template_id, :links]) }

          f.write(goals.to_json)
        }

        input_filenames << RESOURCES_FILENAME

        File.open(File.join(dir, RESOURCES_FILENAME), 'w') do |f|
          resources = []

          template.resources.each do |r|
            resources << ResourceSerializer.new(r)
              .serializable_hash(:include => [])
              .except!(*[:id, :type, :code, :dynamic, :template_id, :links])

            if r.type == Resource::FILE
              filename = "#{RESOURCE}-#{Digest::SHA1.hexdigest(r.name)}"
              input_filenames << filename

              File.open(File.join(dir, filename), 'w') { |b|
                ActiveStorage::Downloader.new(r.file.blob)
                  .download_blob_to_file(b)
              }
            end
          end

          f.write(resources.to_json)
        end

        input_filenames << ATTACHMENTS_FILENAME

        File.open(File.join(dir, ATTACHMENTS_FILENAME), 'w') { |f|
          attachments = []
          template.attachments.each do |a|
            attachment = AttachmentSerializer.new(a)
              .serializable_hash(:include => [])
              .except!(*[:id, :template_id, :resource_id, :links])

            attachment[:resource_name] = Resource.where(
              :id => a.resource_id).pluck(:name)[0]

            attachments << attachment
          end

          f.write(attachments.to_json)
        }

        Zip::File.open(zip_path, Zip::File::CREATE) do |zip|
          input_filenames.each { |f| zip.add(f, File.join(dir, f)) }
        end

        mark
      end

      return zip_file_response
    end

    def tick
      true
    end

    def finished?
      idle_for > expiry_timeout
    end

    def zip_path
      redis.with { |r| r.get(zip_path_key_name) }
    end

    def zip_path=(value)
      redis.with { |r| r.set(zip_path_key_name, value) }
    end

    ###

    def zip_path_key_name
      self.class.zip_path_key_name(instance_id)
    end

  private
    def zip_file_response
      reply_queue = reply_queue_key_name
      response(result(FILE, zip_path), reply_queue)

      location = Rails.application.routes.url_helpers.url_for(
        :controller => :workers, :action => :files, :only_path => true,
        :queue_id => reply_queue_id(reply_queue))

      return result(SUCCESS, { :url => location })
    end
end
