require 'csv'

class TargetsController < ApplicationController
  include Renderable

  before_action :set_target, only: [:show, :update, :destroy]

  # GET /targets
  def index
    @targets = Target.all

    render_collection @targets
  end

  # GET /targets/1
  def show
    render_instance @target
  end

  # POST /targets
  def create
    @target = Target.new(target_params)

    if @target.save
      render_instance @target, { status: :created, location: @target }
    else
      render_errors @target.errors, { status: :unprocessable_entity }
    end
  end

  # PATCH/PUT /targets/1
  def update
    if @target.update(target_params)
      render_instance @target
    else
      render_errors @target.errors, { status: :unprocessable_entity }
    end
  end

  # DELETE /targets/1
  def destroy
    @target.destroy
  end

  # POST /targets/upload
  # PUT /targets/upload
  def upload
    begin
      hash = params.permit(:file, :group_id, :"Content-Type").to_unsafe_h
      Target.upload_csv(hash.delete(:file), hash)
      head :no_content
    rescue CSV::MalformedCSVError, ArgumentError => e
      multi_logger.error{"Unable to parse CSV file, #{e.class}: #{e.message}"}
      multi_logger.backtrace(e)
      render_errors({ :file => [ e.message ] }, { status: :bad_request })
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_target
      @target = Target.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through
    def target_params
      params.require(:target).permit(:first_name, :last_name, :gender,
        :department, :email, :comment, :group_id)
    end
end
