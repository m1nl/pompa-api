class VictimReportsController < ApplicationController
  include Renderable

  before_action :set_victim_report, only: [:show]

  # GET /victim_reports/1/report
  def show
    render_instance @victim_report
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_victim_report
      @victim_report = VictimReport.find(params[:id])
    end
end
