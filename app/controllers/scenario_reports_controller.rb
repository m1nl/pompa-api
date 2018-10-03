class ScenarioReportsController < ApplicationController
  include Renderable

  before_action :set_scenario_report, only: [:show]

  # GET /scenario_reports/1/report
  def show
    render_instance @scenario_report
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_scenario_report
      @scenario_report = ScenarioReport.find(params[:id])
    end
end
