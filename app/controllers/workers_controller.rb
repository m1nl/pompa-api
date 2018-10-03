class WorkersController < ApplicationController
  before_action :set_worker, only: [:show]

  # GET /workers
  def index
    @workers = Worker.all

    render json: @workers
  end

  # GET /attachments/1
  def show
    render json: @worker
  end

  private
    def set_worker
      @worker = Worker.find_by_id(params[:id])
    end
end
