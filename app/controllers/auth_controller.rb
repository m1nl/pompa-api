class AuthController < ApplicationController
  NAME_IDENTIFIER_FORMAT = 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'.freeze

  rescue_from Pompa::Authentication::AuthenticationError,
    :with => :forbidden_error
  rescue_from Pompa::Authentication::AccessError,
    :with => :forbidden_error
  rescue_from Pompa::Authentication::ManipulationError,
    :with => :forbidden_error

  skip_authentication_for :metadata, :init, :callback, :token

  # GET /auth
  def index
    return render :json => authentication_token
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

    return redirect_to url.to_s, status: :see_other
  end

  # POST /auth/token
  def token
    return head :bad_request if [:code, :nonce].any? { |p|
      params[p].blank? }

    code = params[:code]
    nonce = params[:nonce]

    payload = Pompa::Authentication::Token.validate(code, nonce)
    return head :forbidden if !payload[:authenticated] ||
      payload[:client_id].blank?

    self.authenticated_client_id = payload[:client_id]
    return head :forbidden if current_user.nil?

    authorize :auth, :token?

    return render :json => { token:
      Pompa::Authentication::Token.generate_token(authenticated_client_id) }
  end

  # POST /auth/refresh
  def refresh
    return render :json => { token:
      Pompa::Authentication::Token.refresh_token(bearer_token) }
  end

  # POST /auth/revoke
  def revoke
    Pompa::Authentication::Token.revoke_token(bearer_token)
    return head :no_content
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
end