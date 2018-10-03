require 'zip'

module Pompa
  module ResourceTransforms
    class Zip
      DEFAULT_FILENAME = 'content{{ resource.extension }}'.freeze

      ZIP_MIME_TYPE = 'application/zip'.freeze
      ZIP_EXTENSION = '.zip'.freeze

      CONTENT_TYPE = 'content_type'.freeze
      EXTENSION = 'extension'.freeze

      def initialize(params = {})
        @params = params
        @filename_template = Liquid::Template.parse(
          params[:filename] || DEFAULT_FILENAME)
        @password_template = Liquid::Template.parse(
          params[:password] || '')
      end

      def transform_content(input, model, opts)
        filename = @filename_template.render!(
          model, opts[:liquid_flags])
        password = @password_template.render!(
          model, opts[:liquid_flags])

        encrypter = ::Zip::TraditionalEncrypter
          .new(password) if !password.blank?

        stream = ::Zip::OutputStream
          .write_buffer(::StringIO.new(''), encrypter) do |zip|
          entry = ::Zip::Entry.new(nil, filename)
          entry.fstype = ::Zip::FSTYPE_FAT

          zip.put_next_entry(entry)
          input.call { |c| zip.write c }
        end

        yield stream.string
      end

      def transform_model!(name, model, opts)
        model[name][CONTENT_TYPE] = ZIP_MIME_TYPE.dup
        model[name][EXTENSION] = ZIP_EXTENSION.dup
      end
    end
  end
end
