# Đăng nhập bằng Zalo in the Mini App (#152), the same way as on the web (ZaloSessionsController):
# a known Zalo id signs in; else the Zalo phone (zmp-sdk getPhoneNumber, #98) links an owner or staff member without Zalo;
# else 403 not_registered with a registration_token (30 minutes) for owner registration (RegistrationsController).
class MiniApp::V1::SessionsController < MiniApp::V1::BaseController
  skip_before_action :authenticate, only: :create
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { render json: { error: "rate_limited", message: "Thử lại sau ít phút." }, status: :too_many_requests }

  def create
    access_token = params[:access_token].to_s
    zalo = ZaloIdentity.me(access_token)
    return render json: { error: "zalo_rejected", message: "Zalo chưa xác nhận được tài khoản. Thử lại." }, status: :unauthorized unless zalo

    user = User.find_by(zalo_id: zalo[:id]) ||
      (User.link_zalo_by_phone(ZaloIdentity.phone(access_token, params[:phone_token].to_s), zalo[:id]) if params[:phone_token].present?)
    return not_registered(zalo) unless user

    api_token = user.api_tokens.create!(user_agent: request.user_agent.to_s.first(255).presence)
    render json: { token: api_token.token, expires_at: api_token.expires_at, **me_json(user) }, status: :created
  end

  def destroy
    Current.api_token.destroy!
    head :no_content
  end

  private
    # The Zalo id travels only inside the signed token, never as a plain param (like session[:registration] on the web).
    def not_registered(zalo)
      render json: { error: "not_registered", message: "Tài khoản Zalo này chưa có trong hueni.",
                     registration_token: MiniApp::V1::RegistrationsController.token_for(zalo),
                     registration: MiniApp::V1::RegistrationsController.request_json(RegistrationRequest.where(zalo_id: zalo[:id]).order(:id).last) },
        status: :forbidden
    end
end
