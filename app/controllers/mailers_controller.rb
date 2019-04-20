class MailersController < ApplicationController
  include Renderable

  PASSWORD_MAGIC = (' ' * 8).freeze

  before_action :set_mailer, only: [:show, :update, :destroy]

  # GET /mailers
  def index
    @mailers = Mailer.all

    render_collection @mailers
  end

  # GET /mailers/1
  def show
    render_instance @mailer
  end

  # POST /mailers
  def create
    @mailer = Mailer.new(mailer_params)

    if @mailer.save
      render_instance @mailer, status: :created, location: @mailer
    else
      render_errors @mailer.errors, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /mailers/1
  def update
    params = sanitize_password(mailer_params)

    if @mailer.update(params)
      render_instance @mailer
    else
      render_errors @mailer.errors, status: :unprocessable_entity
    end
  end

  # DELETE /mailers/1
  def destroy
    @mailer.destroy
  end

  protected
    def record_not_unique(error)
      render :json => { :errors => { :name => [NOT_UNIQUE] } },
        :status => :unprocessable_entity
    end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_mailer
      @mailer = Mailer.find(params[:id])
    end

    def sanitize_password(params)
      params.delete(:password) if params[:password] == PASSWORD_MAGIC

      return params
    end

    # Only allow a trusted parameter "white list" through.
    def mailer_params
      params.require(:mailer).permit(:name, :host, :port, :username, :password,
        :sender_email, :sender_name, :ignore_certificate, :per_minute, :burst)
    end
end
