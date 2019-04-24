class CampaignsController < ApplicationController
  include Renderable

  before_action :set_campaign, only: [:show, :update, :destroy, :start, :pause, :finish]

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
      render_errors @campaign.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /campaigns/1
  def update
    if @campaign.update(campaign_params)
      render_instance @campaign
    else
      render_errors @campaign.errors, status: :unprocessable_entity
    end
  end

  # DELETE /campaigns/1
  def destroy
    @campaign.destroy
  end

  # POST /campaigns/1/start
  def start
    render_worker_request @campaign.start
  end

  # POST /campaigns/1/pause
  def pause
    render_worker_request @campaign.pause
  end

  # POST /campaigns/1/finish
  def finish
    render_worker_request @campaign.finish
  end

  protected
    def record_not_unique(error)
      render :json => { :errors => { :name => [NOT_UNIQUE] } },
        :status => :unprocessable_entity
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
