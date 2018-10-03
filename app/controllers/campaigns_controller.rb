class CampaignsController < ApplicationController
  include Renderable

  before_action :set_campaign, only: [:show, :update, :destroy, :start, :pause, :finish, :synchronize_events]

  # GET /campaigns
  def index
    @campaigns = Campaign.all

    render_collection @campaigns
  end

  # GET /campaigns/1
  def show
    render_instance @campaign
  end

  # POST /campaigns
  def create
    @campaign = Campaign.new(campaign_params)

    if @campaign.save
      render_instance @campaign, status: :created, location: @campaign
    else
      render_instance @campaign.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /campaigns/1
  def update
    if @campaign.update(campaign_params)
      render_instance @campaign
    else
      render_instance @campaign.errors, status: :unprocessable_entity
    end
  end

  # DELETE /campaigns/1
  def destroy
    @campaign.destroy
  end

  # POST /campaigns/1/start
  def start
    render_worker_response WorkerResponse.wrap(
      @campaign.start(sync: true))
  end

  # POST /campaigns/1/pause
  def pause
    render_worker_response WorkerResponse.wrap(
      @campaign.pause(sync: true))
  end

  # POST /campaigns/1/finish
  def finish
    render_worker_response WorkerResponse.wrap(
      @campaign.finish(sync: true))
  end

  # POST /campaigns/1/synchronize-events
  def synchronize_events
    @campaign.synchronize_events
    head :no_content
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_campaign
      @campaign = Campaign.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def campaign_params
      params.require(:campaign).permit(:name, :description, :start_date,
        :finish_date)
    end
end
