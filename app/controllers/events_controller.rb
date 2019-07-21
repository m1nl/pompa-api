class EventsController < ApplicationController
  include Renderable

  SECOND = 'second'.freeze
  MINUTE = 'minute'.freeze
  HOUR = 'hour'.freeze
  DAY = 'day'.freeze
  WEEK = 'week'.freeze

  PERMITTED_PERIODS = [SECOND, MINUTE, HOUR, DAY, WEEK].freeze

  before_action :set_event, only: [:show, :update, :destroy]

  # GET /events
  def index
    @events = Event.all

    render_collection @events
  end

  # GET /events/1
  def show
    render_instance @event
  end

  # POST /events
  def create
    @event = Event.new(event_params)

    if @event.save
      render_instance @event, status: :created, location: @event
    else
      render_instance @event.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /events/1
  def update
    if @event.update(event_params)
      render_instance @event
    else
      render_instance @event.errors, status: :unprocessable_entity
    end
  end

  # DELETE /events/1
  def destroy
    @event.destroy
  end

  # GET /events/series/day
  def series
    @events = Event.all
    @period = period_param

    render_collection(@events, :ignore => [:include, :join, :quicksearch,
      :page, :sort, :distinct]) do |e|
      goals = Goal.where(:id => e.distinct(:goal_id).pluck(:goal_id))
      series = []

      goals.each do |g|
        goal = GoalSerializer.new(g).serializable_hash(:include => [])
          .except(*[:links])
        series.push(
          {
            :goal => goal, :data => e.joins(:goal).where(goal_id: g.id)
              .group_by_period(@period, :reported_date, series: false,
                format: lambda { |k| k.to_time.rfc3339 })
                .count
          })
      end

      { :event_series => series }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_event
      @event = Event.find(params[:id])
    end

    # Only allow a trusted parameter "white list" through.
    def event_params
      params.require(:event).permit(:reported_date, :data, :goal_id, :victim_id)
    end

    def period_param
      period = params.fetch(:period)
      period = period.to_s unless period.nil?

      period = PERMITTED_PERIODS.include?(period) ? period : HOUR
      period.to_sym
    end
end
