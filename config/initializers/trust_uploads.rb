if Rails.configuration.pompa.trust_uploads
  require 'paperclip/io_adapters/uploaded_file_adapter'

  module Paperclip
    class UploadedFileAdapter
      private
        def content_type_detector
          nil
        end
    end
  end
end
