class VictimsController < ApplicationController
  include Renderable

  before_action :set_victim, only: [:show, :destroy, :send_email, :reset_state]

  # GET /victims
  def index
    @victims = Victim.all

    render_collection @victims
  end

  # GET /victims/1
  def show
    render_instance @victim
  end

  # DELETE /victims/1
  def destroy
    @victim.destroy
  end

  # POST /victims/1/send-email
  def send_email
    render_worker_response WorkerResponse.wrap(
      @victim.send_email(:sync => true))
  end

  # POST /victims/1/reset-state
  def reset_state
    render_worker_response WorkerResponse.wrap(
      @victim.reset_state(:sync => true))
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_victim
      @victim = Victim.find(params[:id])
    end
end
