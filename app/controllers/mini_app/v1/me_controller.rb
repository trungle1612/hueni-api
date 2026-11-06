# Who is signed in and their homestays (#152).
class MiniApp::V1::MeController < MiniApp::V1::BaseController
  def show = render(json: me_json(Current.user))

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
