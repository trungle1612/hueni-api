# Zalo login and linking (#97). A Zalo id is bound to an account only when we know who it is: through a
# one-time link (/dat-mat-khau/:token), while logged in, or by the Zalo account's phone number (#98).
# Never creates accounts: an unknown Zalo goes to owner registration (/dang-ky), which an admin approves.
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
      if (user = User.find_by(zalo_id:) || link_by_phone(zalo_id))
        start_new_session_for user
        redirect_to after_authentication_url, notice: ("Bạn đã có tài khoản." if request.env.dig("omniauth.params", "register"))
      else
        start_registration(zalo_id)
      end
    end

    # The Zalo id stays in the (encrypted) session for 30 minutes: RegistrationsController never takes it from params.
    def start_registration(zalo_id)
      session[:registration] = { "zalo_id" => zalo_id, "zalo_name" => request.env.dig("omniauth.auth", "info", "name").to_s,
                                 "expires_at" => 30.minutes.from_now.to_i }
      redirect_to registration_path
    end

    # #98: with Zalo's phone permission, the number on the Zalo account (verified by Zalo) links an owner or
    # staff member who has none yet. `normalizes` turns Zalo's 84… / +84… into our 0…. Never admins.
    def link_by_phone(zalo_id)
      phone = request.env.dig("omniauth.auth", "extra", "raw_info", "phone").to_s
      return if phone.blank?

      user = User.user.find_by(phone_number: phone, zalo_id: nil)
      user if user&.update(zalo_id:)
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
