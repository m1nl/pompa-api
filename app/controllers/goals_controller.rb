class GoalsController < ApplicationController
  include Renderable

  before_action :set_goal, only: [:show, :update, :destroy]

  # GET /goals
  def index
    @goals = Goal.all

    render_collection @goals
  end

  # GET /goals/1
  def show
    render_instance @goal
  end

  # POST /goals
  def create
    @goal = Goal.new(goal_params)

    if @goal.save
      render_instance @goal, status: :created, location: @goal
    else
      render_errors @goal.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /goals/1
  def update
    if @goal.update(goal_params)
      render_instance @goal
    else
      render_errors @goal.errors, status: :unprocessable_entity
    end
  end

  # DELETE /goals/1
  def destroy
    @goal.destroy
  end

  protected
    def record_not_unique(error)
      render :json => { :errors => { :name => [NOT_UNIQUE] } },
        :status => :unprocessable_entity
    end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_goal
      @goal = Goal.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def goal_params
      params.require(:goal).permit(:name, :description, :code, :score, :template_id)
    end
end
