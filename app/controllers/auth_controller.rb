class AuthController < ApplicationController
  NAME_IDENTIFIER_FORMAT = 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'.freeze

  rescue_from Pompa::Authentication::AuthenticationError,
    :with => :handle_error
  rescue_from Pompa::Authentication::ValidationError,
    :with => :handle_error

  skip_authentication_for :metadata, :init, :callback, :token

  # GET /auth
  def index
    return render :json => { client_id: client_id }
  end

  # GET /auth/metadata
  def metadata
    return render :xml => saml_meta
  end

  # POST /auth/init
  def init
    return head :bad_request if params[:return_url].blank?

    begin
      url = Addressable::URI.parse(params[:return_url])
    rescue Addressable::URI::InvalidURIError
      return head :unprocessable_entity
    end

    saml_request = OneLogin::RubySaml::Authrequest.new
    saml_url = saml_request.create(saml_settings)

    nonce = Pompa::Authentication::Token.preauthenticate(
      saml_request.uuid, return_url: url.to_s)

    return render :json => { nonce: nonce, redirect_url: saml_url }
  end

  # POST /auth/callback
  def callback
    return head :bad_request if params[:SAMLResponse].blank?

    response = OneLogin::RubySaml::Response.new(
      params.fetch(:SAMLResponse), :settings => saml_settings)

    if !response.is_valid?
      multi_logger.error(["SAML response invalid - errors: ", response.errors],
        no_truncate: true)
      return head :bad_request
    end

    client_id = response.name_id
    return head :bad_request if client_id.blank?

    code = response.in_response_to
    data = Pompa::Authentication::Token.authenticate(code, client_id: client_id)

    return_url = data[:return_url]
    return head :no_content if return_url.blank?

    url = nil

    begin
      url = Addressable::URI.parse(return_url)
    rescue Addressable::URI::InvalidURIError
      return head :no_content
    end

    url.query_values = (url.query_values || {}).merge(code: code)

    return redirect_to url.to_s, status: :found
  end

  # POST /auth/token
  def token
    return head :bad_request if [:code, :nonce].any? { |p|
      !params[p].blank? }

    code = params[:code]
    nonce = params[:nonce]

    payload = Pompa::Authentication::Token.validate(code, nonce)

    return head :forbidden if !payload[:authenticated] ||
      payload[:client_id].blank?

    return render :json => { token: generate_token(payload[:client_id]) }
  end

  # POST /auth/refresh
  def refresh
    return render :json => { token: refresh_token(bearer_token) }
  end

  private
    def saml_meta
      return @saml_meta if !@saml_meta.nil?

      meta = OneLogin::RubySaml::Metadata.new
      @saml_meta = meta.generate(saml_settings, true)
    end

    def saml_settings
      return @saml_settings if !@saml_settings.nil?

      saml_settings = OneLogin::RubySaml::Settings.new

      saml_settings.assertion_consumer_service_url =
        url_for(:action => :callback)

      saml_settings.issuer = url_for(:action => :metadata)

      saml_settings.idp_entity_id = Rails.configuration
        .pompa.authentication.idp_entity_id

      saml_settings.idp_sso_target_url = Rails.configuration
        .pompa.authentication.idp_sso_target_url

      saml_settings.idp_cert = Rails.configuration
        .pompa.authentication.idp_cert
 
      saml_settings.name_identifier_format = NAME_IDENTIFIER_FORMAT

      return saml_settings
    end

    def handle_error(e)
      multi_logger.error{"Error in #{self.class.name}, #{e.class}: #{e.message}"}
      multi_logger.backtrace(e)

      return head :forbidden
    end
end
