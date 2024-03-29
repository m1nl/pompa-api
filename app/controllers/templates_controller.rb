class TemplatesController < ApplicationController
  include Renderable

  allow_temporary_token_for :import

  before_action :set_template, only: [:show, :update, :destroy, :duplicate, :export]

  # GET /templates
  def index
    @templates = Template.all

    render_collection @templates
  end

  # GET /templates/1
  def show
    render_instance @template
  end

  # POST /templates
  def create
    @template = Template.new(template_params)

    if @template.save
      render_instance @template, status: :created, location: @template
    else
      render_errors @template.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /templates/1
  def update
    if @template.update(template_params)
      render_instance @template
    else
      render_errors @template.errors, status: :unprocessable_entity
    end
  end

  # DELETE /templates/1
  def destroy
    @template.destroy
  end

  # POST /templates/1/duplicate
  def duplicate
    render_instance @template.duplicate
  end

  # POST /templates/1/export
  def export
    render_worker_request @template.export
  end

  # POST /templates/import
  # PUT /templates/import
  def import
    hash = params.permit(:file, :'Content-Type').to_unsafe_h
    file = File.open(hash[:file].path)
    filename = hash[:file].original_filename

    blob = ActiveStorage::Blob.create_and_upload!(io: file, filename: filename)
    render_worker_request Template.import(blob.id)
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_template
      @template = Template.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def template_params
      params.require(:template).permit(:name, :description, :sender_email,
        :sender_name, :base_url, :landing_url, :report_url,
        :static_resource_url, :dynamic_resource_url, :subject, :plaintext,
        :html, :phishing_report_goal_id)
    end
end
