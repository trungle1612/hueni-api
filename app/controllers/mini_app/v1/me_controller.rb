# Who is signed in and their homestays (#152).
class MiniApp::V1::MeController < MiniApp::V1::BaseController
  def show = render(json: me_json(Current.user))

  # Xoá tài khoản (#192): the signed-in user, themselves only. The Mini App asks with one confirm sheet first.
  def destroy
    Current.user.delete_account!
    head :no_content
  end

  # Cài đặt thông báo (#213): { off: [type] }, the optional types this user hides; Trùng phòng và lỗi kênh stays on.
  def notifications
    Current.user.update!(notifications_off: Array(params[:off]) & Notification::OPTIONAL)
    head :no_content
  end

  # Consent for a user already linked (signed in by a known Zalo id, or a newer policy version, #206).
  def terms
    return render_terms_required if params[:version].blank?

    if Current.user.update(terms_version: params[:version], terms_accepted_at: Time.current)
      head :no_content
    else
      render_invalid(Current.user)
    end
  end
end
