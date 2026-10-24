# Đăng nhập bằng Zalo in the Mini App (#152): zmp-sdk access token → Zalo user id → our API token.
# Only accounts already linked to Zalo on the web (#97); registration stays there.
class MiniApp::V1::SessionsController < MiniApp::V1::BaseController
  skip_before_action :authenticate, only: :create
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { render json: { error: "rate_limited", message: "Thử lại sau ít phút." }, status: :too_many_requests }

  def create
    zalo_id = ZaloIdentity.id_for(params[:access_token].to_s)
    return render json: { error: "zalo_rejected", message: "Zalo chưa xác nhận được tài khoản. Thử lại." }, status: :unauthorized unless zalo_id
    user = User.find_by(zalo_id:)
    unless user
      return render json: { error: "not_registered", message: "Tài khoản Zalo này chưa có trong hueni. Đăng ký hoặc nhờ chủ cơ sở thêm bạn trên trang quản trị hueni." },
        status: :forbidden
    end
    api_token = user.api_tokens.create!(user_agent: request.user_agent.to_s.first(255).presence)
    render json: { token: api_token.token, expires_at: api_token.expires_at, **me_json(user) }, status: :created
  end

  def destroy
    Current.api_token.destroy!
    head :no_content
  end
end
