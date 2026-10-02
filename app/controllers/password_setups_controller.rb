# The one-time link from /admin/users: the owner chooses a password and is logged in. Works once, for 7 days.
class PasswordSetupsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :update, with: -> { redirect_to new_session_path, alert: "Thử lại sau ít phút." }
  before_action :set_user

  def edit
  end

  def update
    password, confirmation = params.expect(user: %i[password password_confirmation]).values_at(:password, :password_confirmation)
    # has_secure_password silently ignores a blank password on update, which would log in without setting one.
    if password.present? && @user.update(password:, password_confirmation: confirmation)
      @user.sessions.destroy_all
      start_new_session_for @user
      redirect_to admin_root_url, notice: "Đã lưu mật khẩu. Chào #{@user.name}!"
    else
      @user.errors.add(:password, :blank) if password.blank?
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def set_user
      @user = User.find_by_token_for(:password_setup, params[:token])
      render :expired, status: :not_found unless @user
    end
end
