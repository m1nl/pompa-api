class ScenariosController < ApplicationController
  include Renderable

  rescue_from Scenario::InvalidState, :with => :scenario_invalid_state

  CSV_CONTENT_TYPE = 'text/csv; charset=UTF-8'.freeze
  CSV_EXTENSION = '.csv'.freeze

  CONTENT_TYPE_HEADER = 'Content-Type'.freeze
  CONTENT_DISPOSITION_HEADER = 'Content-Disposition'.freeze
  LAST_MODIFIED_HEADER = 'Last-Modified'.freeze

  allow_temporary_token_for :victims_summary

  before_action :set_scenario, only: [:show, :update, :destroy, :victims_summary, :synchronize_group]

  # GET /scenarios
  def index
    @scenarios = Scenario.all

    render_collection @scenarios
  end

  # GET /scenarios/1
  def show
    render_instance @scenario
  end

  # POST /scenarios
  def create
    @scenario = Scenario.new(scenario_params)

    if @scenario.save
      render_instance @scenario, status: :created, location: @scenario
    else
      render_errors @scenario.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /scenarios/1
  def update
    if @scenario.update(scenario_params)
      render_instance @scenario
    else
      render_errors @scenario.errors, status: :unprocessable_entity
    end
  end

  # DELETE /scenarios/1
  def destroy
    @scenario.destroy
  end

  # GET /scenarios/1/victims-summary
  def victims_summary
    filename = "victims_summary_#{@scenario.id}_#{Time.current.to_i}#{CSV_EXTENSION}"

    response.headers[CONTENT_TYPE_HEADER] = CSV_CONTENT_TYPE
    response.headers[CONTENT_DISPOSITION_HEADER] =
      Pompa::Utils.content_disposition(filename)
    response.headers[LAST_MODIFIED_HEADER] = Time.current.httpdate

    self.status = :ok
    self.response_body = @scenario.victims_summary_csv
  end

  # POST /scenarios/1/synchronize-group
  def synchronize_group
    @scenario.synchronize_group
    head :no_content
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_scenario
      @scenario = Scenario.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def scenario_params
      params.require(:scenario).permit(:campaign_id, :template_id, :mailer_id,
        :group_id)
    end

    def scenario_invalid_state(error)
      render_errors([{ :record => [error.message] }])
    end
end
