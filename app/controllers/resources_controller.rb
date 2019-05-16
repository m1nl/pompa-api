require 'rack/mime'

class ResourcesController < ApplicationController
  include Renderable

  DEFAULT_DISPOSITION = 'attachment; filename="%s"'.freeze

  CONTENT_TYPE_HEADER = 'Content-Type'.freeze
  CONTENT_DISPOSITION_HEADER = 'Content-Disposition'.freeze
  LAST_MODIFIED_HEADER = 'Last-Modified'.freeze

  before_action :set_resource, only: [:show, :update, :destroy, :download, :upload]

  # GET /resources
  def index
    @resources = Resource.with_attached_file.all

    render_collection @resources
  end

  # GET /resources/1
  def show
    render_instance @resource
  end

  # POST /resources
  def create
    @resource = Resource.new(resource_params)

    if @resource.save
      render_instance @resource, status: :created, location: @resource
    else
      render_errors @resource.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /resources/1
  def update
    if @resource.update(resource_params)
      render_instance @resource
    else
      render_errors @resource.errors, status: :unprocessable_entity
    end
  end

  # DELETE /resources/1
  def destroy
    @resource.destroy
  end

  # GET /resources/1/download
  def download
    return head :forbidden if @resource.dynamic_url?

    filename = ""

    if @resource.type == Resource::FILE
      filename = @resource.file.filename.sanitized
    end

    if filename.blank?
      filename = "resource_#{@resource.id}#{@resource.real_extension}"
    end

    response.headers[CONTENT_TYPE_HEADER] = @resource.real_content_type
    response.headers[CONTENT_DISPOSITION_HEADER] =
      DEFAULT_DISPOSITION % filename
    response.headers[LAST_MODIFIED_HEADER] ||= Time.current.httpdate

    self.status = :ok
    self.response_body = Resource::ContentWrapper.new(@resource,
      :error_handler => method(:handle_streaming_error))
  end

  # POST /resources/1/upload
  # PUT /resources/1/upload
  def upload
    @resource.update(file: params.require(:file))
    head :no_content
  end

  protected
    def record_not_unique(error)
      render :json => { :errors => { :name => [NOT_UNIQUE] } },
        :status => :unprocessable_entity
    end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_resource
      @resource = Resource.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def resource_params
      params.require(:resource).permit(:name, :description, :url, :file,
        :content_type, :extension, :code, :dynamic_url, :render_template,
        :template_id).tap do |tap|
        Pompa::Utils.permit_raw(params.fetch(:resource), tap, :transforms)
      end
    end

    def handle_streaming_error(e)
      error_message = "Error in #{self.class.name}, #{e.class}: #{e.message}"

      multi_logger.error(error_message)
      multi_logger.backtrace(e)

      "<!-- #{error_message} -->"
    end
end
