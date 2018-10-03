class ResourceSerializer < ApplicationSerializer
  attributes :id, :name, :description, :type, :url, :file, :content_type, :extension, :dynamic_url, :render_template, :code, :transforms, :template_id, :dynamic

  belongs_to :template
  has_many :attachments

  def file
    if object.type == Resource::FILE
      return { filename: object.file.original_filename, content_type: object.file.content_type, size: object.file.size }
    else
      return nil
    end
  end

  def dynamic
    object.dynamic?
  end

  def links
    links = super
    links.merge!({ :template => Rails.application.routes
      .url_helpers.url_for(:controller => :templates, :action => :show,
        :only_path => true, :id => object.template_id) })
    links.merge!({ :attachments => Rails.application.routes
      .url_helpers.url_for(:controller => :attachments, :action => :index,
        :only_path => true, :filter => { :resource_id => object.id }) })
  end
end
