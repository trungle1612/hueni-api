# Mã mời on Thành viên (#211), owners only, like the Mini App: staff codes, 7 days, one use.
# Admins (members of the homestay, #85) also pick the role, uses and days: owner codes for Zalo review.
class Admin::InvitesController < Admin::BaseController
  before_action :set_place
  before_action -> { authorize!(:manage, @place) }

  def create
    attrs = Current.user.admin? ? params.expect(invite: %i[role max_uses days]) : {}
    invite = @place.invites.build(role: attrs[:role].presence || "staff", max_uses: attrs[:max_uses].presence || 1,
      expires_at: (attrs[:days].presence || 7).to_i.clamp(1, 30).days.from_now, created_by: Current.user)
    if invite.save
      redirect_to admin_place_path(@place.slug, anchor: "members"), notice: "Đã tạo mã mời #{invite.display_code}."
    else
      redirect_to admin_place_path(@place.slug, anchor: "members"), alert: invite.errors.full_messages.to_sentence
    end
  end

  def destroy
    @place.invites.find(params[:id]).destroy!
    redirect_to admin_place_path(@place.slug, anchor: "members"), notice: "Đã thu hồi mã mời."
  end

  private
    def set_place
      @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    end
end
