require 'tmpdir'
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
        blob_id = r.get(blob_id_key_name(opts[:instance_id]))

        begin
          blob = ActiveStorage::Blob.find_by_id(blob_id)
          blob.purge if !blob.nil? && !keep_file
        rescue StandardError
        end

        r.del(blob_id_key_name(opts[:instance_id]))
        r.del(template_id_key_name(opts[:instance_id]))
      end
    end

    def blob_id_key_name(instance_id)
      "#{name}:#{instance_id}:blob_id"
    end

    def template_id_key_name(instance_id)
      "#{name}:#{instance_id}:template_id"
    end
  end

  protected
    def invoke(opts = {})
      super(opts)

      self.template_id = opts.delete(:template_id)
      return result(INVALID) if template_id.nil?

      template = Template.find_by_id(template_id)
      return result(INVALID) if template.nil?

      zip_path = File.join(Pompa::Utils.shared_tmpdir,
        "#{TEMPLATE}-#{Pompa::Utils.uuid}.#{ZIP}")

      begin
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

                File.open(File.join(dir, filename), 'wb') { |f|
                  r.file.download { |c| f.write(c) }
                }

                mark
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
                :id => a.resource_id).pick(:name)

              attachments << attachment
            end

            f.write(attachments.to_json)
          }

          Zip::File.open(zip_path, Zip::File::CREATE) do |zip|
            input_filenames.each { |f| zip.add(f, File.join(dir, f)) }
          end

          mark
        end

        return zip_file_response(zip_path)
      rescue Zip::Error => e
        logger.error("Template export error: #{e.class.name}: #{e.message}")
        multi_logger.backtrace(e)
        return result(ERROR, "error reading ZIP archive: #{e.message}")
      rescue StandardError => e
        logger.error("Template export error: #{e.class.name}: #{e.message}")
        multi_logger.backtrace(e)
        return result(ERROR, "#{e.class.name}: #{e.message}")
      ensure
        begin
          File.delete(zip_path) if !zip_path.blank? && File.file?(zip_path)
        rescue StandardError
        end
      end
    end

    def tick
      true
    end

    def finished?
      true
    end

    ###

    def blob_id
      redis.with { |r| r.get(blob_id_key_name) }
    end

    def template_id
      redis.with { |r| r.get(template_id_key_name) }
    end

    def template_id=(value)
      redis.with { |r| r.set(template_id_key_name, value) }
    end

    ###

    def blob_id_key_name
      self.class.blob_id_key_name(instance_id)
    end

    def template_id_key_name
      self.class.template_id_key_name(instance_id)
    end

  private
    def zip_file_response(zip_path)
      file = File.open(zip_path)
      timestamp = Time.now.utc.strftime("%y%m%d%H%M%S")
      filename = "#{TEMPLATE}-#{template_id}-#{timestamp}.#{ZIP}"

      blob_id = ActiveStorage::Blob.create_and_upload!(io: file, filename: filename).id

      reply_queue = reply_queue_key_name
      response(result(FILE, { blob_id: blob_id, filename: filename }), reply_queue)

      location = Rails.application.routes.url_helpers.url_for(
        :controller => :workers, :action => :files, :only_path => true,
        :queue_id => reply_queue_id(reply_queue))

      return result(SUCCESS, { :url => location })
    end
end
