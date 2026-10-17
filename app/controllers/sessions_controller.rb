class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Thử lại sau ít phút." }

  def new
  end

  def create
    # Only admins log in with a password (#97); everyone else gets the same message as a wrong password,
    # so it doesn't reveal the account's role.
    if (user = User.authenticate_by(params.permit(:phone_number, :password)))&.admin?
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path(admin: 1), alert: "Số điện thoại hoặc mật khẩu không đúng."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
