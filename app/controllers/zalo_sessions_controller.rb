# Zalo login and linking (#97). Zalo gives no phone number, so a Zalo id is bound to an account only when
# we already know who it is: through a one-time link (/dat-mat-khau/:token) or while logged in.
# Never creates accounts.
class ZaloSessionsController < ApplicationController
  ALREADY_LINKED = "Tài khoản Zalo này đã liên kết với người dùng khác.".freeze

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Thử lại sau ít phút." }

  def create
    zalo_id = request.env.dig("omniauth.auth", "uid").to_s
    # A failed Graph call still gets here, with a blank uid: never look it up or bind it.
    return failure if zalo_id.blank?

    # ?link= on the POST to /auth/zalo2, from the link page or the logged-in "Liên kết Zalo" button.
    case request.env.dig("omniauth.params", "link")
    when "token" then link_through_setup_link(zalo_id)
    when "me" then link_current_user(zalo_id)
    else log_in(zalo_id)
    end
  end

  def failure
    redirect_to new_session_path, alert: "Đăng nhập Zalo không thành công. Thử lại."
  end

  private
    def log_in(zalo_id)
      if (user = User.find_by(zalo_id:))
        start_new_session_for user
        redirect_to after_authentication_url
      else
        redirect_to new_session_path, alert: "Tài khoản Zalo này chưa được liên kết. Liên hệ quản trị viên."
      end
    end

    # The token (kept in the session by PasswordSetupsController#edit) proves who this is.
    # The new placeholder password consumes the link.
    def link_through_setup_link(zalo_id)
      token = session.delete(:zalo_link_token).to_s
      unless (user = User.find_by_token_for(:password_setup, token))
        return redirect_to new_session_path, alert: "Link đã hết hạn hoặc đã được dùng. Nhờ quản trị viên gửi link mới."
      end

      if user.update(zalo_id:, password: User.unknown_password)
        user.sessions.destroy_all
        start_new_session_for user
        redirect_to admin_root_url, notice: "Đã liên kết Zalo. Chào #{user.name}!"
      else
        redirect_to password_setup_path(token:), alert: ALREADY_LINKED
      end
    end

    def link_current_user(zalo_id)
      return redirect_to new_session_path unless authenticated?

      if Current.user.update(zalo_id:)
        redirect_to admin_root_path, notice: "Đã liên kết Zalo. Lần sau bấm Đăng nhập bằng Zalo."
      else
        redirect_to admin_root_path, alert: ALREADY_LINKED
      end
    end
end
