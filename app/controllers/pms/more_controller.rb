# Thêm (#236): the PWA screens beyond the tabs, homestay switcher, Tài khoản (Điều khoản, Đăng xuất, Xoá tài khoản).
class Pms::MoreController < Pms::BaseController
  def show
  end

  # Xoá tài khoản (#192): the signed-in user, themselves only; same rule as DELETE /api/v1/me. Every session ends with it.
  def destroy
    Current.user.delete_account!
    cookies.delete(:session_id)
    redirect_to new_session_path, status: :see_other, notice: "Đã xoá tài khoản."
  end
end
