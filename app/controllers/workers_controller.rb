require 'oj'

class WorkersController < ApplicationController
  include Renderable

  allow_temporary_token_for :replies, :files

  before_action :set_worker, only: [:show]

  QUANTUM = 1.seconds

  LAST_MODIFIED_HEADER = 'Last-Modified'.freeze

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
        worker_response = nil

        loop do
          worker_response = r.brpop(reply_queue, :timeout => QUANTUM)
          time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if !worker_response.nil? || (time - start) >= timeout
        end

        return render status: :no_content if worker_response.nil?

        json = worker_response[1]
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
        worker_response = nil

        loop do
          worker_response = r.brpop(reply_queue, :timeout => QUANTUM)
          time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          break if !worker_response.nil? || (time - start) >= timeout
        end

        return render status: :no_content if worker_response.nil?

        json = worker_response[1]
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

        blob_id = message.dig(:result, :blob_id)
        filename = message.dig(:result, :filename)

        blob = ActiveStorage::Blob.find_by_id(blob_id)
        return render status: :not_found if blob.nil?

        self.response.headers["Content-Type"] = blob.content_type
        self.response.headers["Content-Disposition"] =
          Pompa::Utils.content_disposition(filename) if !filename.blank?
        self.response.headers[LAST_MODIFIED_HEADER] ||= Time.current.httpdate

        self.status = :ok
        self.response_body = StreamingWrapper.new(blob)
      end
    end
  end

  private
    def set_worker
      @worker = Worker.find_by_id(params[:id])
    end

    class StreamingWrapper
      def initialize(blob, opts = {})
        @blob = blob
      end

      def each
        @blob.download { |c| yield c }
      rescue StandardError => e
        yield handle_streaming_error(e)
      end

      private
        def handle_streaming_error(e)
          error_message = "Error in #{self.class.name}, #{e.class}: #{e.message}"

          multi_logger.error(error_message)
          multi_logger.backtrace(e)

          "<!-- #{error_message} -->"
        end
    end
end
