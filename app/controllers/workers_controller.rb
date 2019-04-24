require 'json'

class WorkersController < ApplicationController
  include Renderable

  before_action :set_worker, only: [:show]

  # GET /workers
  def index
    @workers = Worker.all

    render json: @workers
  end

  # GET /workers/1
  def show
    return record_not_found if @worker.nil?

    render json: @worker
  end

  # GET /workers/replies/1aa36acb-b3bb-4684-86a1-321de1e4f221
  def replies
    sync = !!params[:sync]
    timeout = params[:timeout]

    if !timeout.is_a?(Integer) || timeout > Worker.expiry_timeout
      timeout = Worker.expiry_timeout
    end

    reply_queue_key_name = Worker.reply_queue_key_name(params[:queue_id])

    Pompa::RedisConnection.redis do |r|
      begin
        json = r.lpop(reply_queue_key_name)

        if json.nil? && sync
          response = r.blpop(reply_queue_key_name, :timeout => timeout)
          return render status: :no_content if response.nil?

          json = response[1]
        end

        return render status: :no_content if json.nil?

        render_worker_response WorkerResponse.wrap(
          JSON.parse(json, symbolize_names: true))
      rescue JSON::ParserError => e
        return render status: :no_content
      end
    end
  end

  private
    def set_worker
      @worker = Worker.find_by_id(params[:id])
    end
end
