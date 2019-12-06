require 'oj'

class WorkersController < ApplicationController
  include Renderable

  ATTACHMENT = 'attachment'.freeze
  QUANTUM = 1.seconds

  allow_temporary_token_for :replies, :files

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
      timeout = Worker.queue_timeout
    end

    reply_queue = Worker.reply_queue_key_name(params.slice(*[:queue_id]))
    message = nil

    Pompa::RedisConnection.redis do |r|
      json = r.rpop(reply_queue)

      if json.nil? && sync
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = nil

        loop do
          response = r.brpop(reply_queue, :timeout => QUANTUM)
          time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if !response.nil? || (time - start) >= timeout
        end

        return render status: :no_content if response.nil?

        json = response[1]
      end

      return render status: :no_content if json.nil?

      message = nil

      begin
        message = Oj.load(json, symbol_keys: true)
      rescue Oj::ParseError => e
        return render status: :no_content
      end

      return render status: :no_content if message.nil?

      if message.dig(:result, :status) == Worker::FILE
        r.lpush(reply_queue, json)

        location = Rails.application.routes.url_helpers.url_for(
          :controller => :workers, :action => :files, :only_path => true,
          :queue_id => queue_id, :sync => sync)
        return redirect_to location, status: :see_other
      else
        r.lpush(reply_queue, json) if request.method.downcase.to_sym != :get
        return render_worker_response WorkerResponse.wrap(message)
      end
    end
  end

  # GET /workers/files/1aa36acb-b3bb-4684-86a1-321de1e4f221
  def files
    sync = !!params[:sync]
    timeout = params[:timeout]

    if !timeout.is_a?(Integer) || timeout > Worker.expiry_timeout
      timeout = Worker.queue_timeout
    end

    reply_queue = Worker.reply_queue_key_name(params.slice(*[:queue_id]))
    message = nil

    Pompa::RedisConnection.redis do |r|
      json = r.rpop(reply_queue)

      if json.nil? && sync
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = nil

        loop do
          response = r.brpop(reply_queue, :timeout => QUANTUM)
          time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if !response.nil? || (time - start) >= timeout
        end

        return render status: :no_content if response.nil?

        json = response[1]
      end

      return render status: :no_content if json.nil?

      message = nil

      begin
        message = Oj.load(json, symbol_keys: true)
      rescue Oj::ParseError => e
        return render status: :no_content
      end

      return render status: :no_content if message.nil?

      if message.dig(:result, :status) != Worker::FILE
        r.lpush(reply_queue, json)

        location = Rails.application.routes.url_helpers.url_for(
          :controller => :workers, :action => :replies, :only_path => true,
          :queue_id => queue_id, :sync => sync)
        return redirect_to location, status: :see_other
      else
        r.lpush(reply_queue, json) if request.method.downcase.to_sym != :get

        path = message.dig(:result, :path)
        filename = message.dig(:result, :filename)
        return send_file(path, :filename => filename) if File.file?(path)
        return render status: :not_found
      end
    end
  end

  private
    def set_worker
      @worker = Worker.find_by_id(params[:id])
    end
end
