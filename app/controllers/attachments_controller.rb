class AttachmentsController < ApplicationController
  include Renderable

  before_action :set_attachment, only: [:show, :update, :destroy]

  # GET /attachments
  def index
    @attachments = Attachment.all

    render_collection @attachments
  end

  # GET /attachments/1
  def show
    render_instance @attachment
  end

  # POST /attachments
  def create
    @attachment = Attachment.new(attachment_params)

    if @attachment.save
      render_instance @attachment, status: :created, location: @attachment
    else
      render_errors @attachment.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /attachments/1
  def update
    if @attachment.update(attachment_params)
      render_instance @attachment
    else
      render_errors @attachment.errors, status: :unprocessable_entity
    end
  end

  # DELETE /attachments/1
  def destroy
    @attachment.destroy
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_attachment
      @attachment = Attachment.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def attachment_params
      params.require(:attachment).permit(:name, :filename, :template_id,
        :resource_id)
    end
end
