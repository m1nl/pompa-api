class GroupsController < ApplicationController
  include Renderable

  before_action :set_group, only: [:show, :update, :destroy, :import, :clear]

  # GET /groups
  def index
    @groups = Group.all

    render_collection @groups
  end

  # GET /groups/1
  def show
    render_instance @group
  end

  # POST /groups
  def create
    @group = Group.new(group_params)

    if @group.save
      render_instance @group, { status: :created, location: @group }
    else
      render_errors @group.errors, { status: :unprocessable_entity }
    end
  end

  # PATCH/PUT /groups/1
  def update
    if @group.update(group_params)
      render_instance @group
    else
      render_errors @group.errors, { status: :unprocessable_entity }
    end
  end

  # DELETE /groups/1
  def destroy
    @group.destroy
  end

  # POST /group/1/clear
  def clear
    @group.clear
    head :no_content
  end

  protected
    def record_not_unique(error)
      render :json => { :errors => { :name => [NOT_UNIQUE] } },
        :status => :unprocessable_entity
    end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_group
      @group = Group.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def group_params
      params.require(:group).permit(:name, :description)
    end
end
