class TemplateImportJob < ApplicationJob
  include Pompa::Worker

  def instance_id
    self.job_id
  end

  protected
    def invoke(opts = {})
      super(opts)

      file_path = opts.delete(:file_path)

      return result(INVALID) if file_path.blank? || !File.file?(file_path)

      mark
    end

    def mark
      true
    end

    def finished?
      idle_for > expiry_timeout
    end
end
