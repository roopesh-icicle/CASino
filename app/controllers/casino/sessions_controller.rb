class CASino::SessionsController < CASino::ApplicationController
  include CASino::SessionsHelper
  include CASino::AuthenticationProcessor
  include CASino::TwoFactorAuthenticatorProcessor

  before_action :validate_login_ticket, only: [:create]
  before_action :ensure_service_allowed, only: [:new, :create]
  before_action :load_ticket_granting_ticket_from_parameter, only: [:validate_otp]

  def index
    processor(:TwoFactorAuthenticatorOverview).process(cookies, request.user_agent)
    processor(:SessionOverview).process(cookies, request.user_agent)
  end

  def new
    tgt = current_ticket_granting_ticket
    handle_signed_in(tgt) unless params[:renew] || tgt.nil?
    redirect_to(params[:service]) if params[:gateway] && params[:service].present?
  end

  def create
    validation_result = validate_login_credentials(params[:username], params[:password])
    if !validation_result
      show_login_error I18n.t('login_credential_acceptor.invalid_login_credentials')
    else
      sign_in(validation_result, long_term: params[:rememberMe], credentials_supplied: true)
    end
  end

  def destroy
    processor(:SessionDestroyer).process(params, cookies, request.user_agent)
  end

  def destroy_others
    processor(:OtherSessionsDestroyer).process(params, cookies, request.user_agent)
  end

  def logout
    sign_out
    @url = params[:url]
    if params[:service].present? && service_allowed?(params[:service])
      redirect_to params[:service], status: :see_other
    end
  end

  def validate_otp
    validation_result = validate_one_time_password(params[:otp], @ticket_granting_ticket.user.active_two_factor_authenticator)
    return flash.now[:error] = I18n.t('validate_otp.invalid_otp') unless validation_result.success?
    @ticket_granting_ticket.update_attribute(:awaiting_two_factor_authentication, false)
    handle_signed_in(@ticket_granting_ticket)
  end

  private
  def show_login_error(message)
    flash.now[:error] = message
    render :new, status: :forbidden
  end

  def validate_login_ticket
    unless CASino::LoginTicket.consume(params[:lt])
      show_login_error I18n.t('login_credential_acceptor.invalid_login_ticket')
    end
  end

  def ensure_service_allowed
    if params[:service].present? && !service_allowed?(params[:service])
      render 'service_not_allowed', status: :forbidden
    end
  end

  def load_ticket_granting_ticket_from_parameter
    @ticket_granting_ticket = find_valid_ticket_granting_ticket(params[:tgt], request.user_agent, ignore_two_factor: true)
    return redirect_to login_path if @ticket_granting_ticket.nil?
  end
end
