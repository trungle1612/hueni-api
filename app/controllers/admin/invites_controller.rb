# Mã mời (#211), owners only, like the Mini App: staff codes, 7 days, one use. Menu Mã mời lists every homestay
# you own; the homestay page shows the same card under Thành viên.
# Admins (members of the homestay, #85) also pick the role, uses and days: owner codes for Zalo review.
class Admin::InvitesController < Admin::BaseController
  before_action :set_place, except: :index
  before_action -> { authorize!(:manage, @place) }, except: :index

  def index
    @places = owned_places
    raise Forbidden if @places.none?
    @invites = Invite.usable.where(place: @places).order(:id).group_by(&:place_id)
  end

  def create
    attrs = Current.user.admin? ? params.expect(invite: %i[role max_uses days]) : {}
    invite = @place.invites.build(role: attrs[:role].presence || "staff", max_uses: attrs[:max_uses].presence || 1,
      expires_at: (attrs[:days].presence || 7).to_i.clamp(1, 30).days.from_now, created_by: Current.user)
    if invite.save
      redirect_back_or_to admin_place_path(@place.slug, anchor: "members"), notice: "Đã tạo mã mời #{invite.display_code}."
    else
      redirect_back_or_to admin_place_path(@place.slug, anchor: "members"), alert: invite.errors.full_messages.to_sentence
    end
  end

  def destroy
    @place.invites.find(params[:id]).destroy!
    redirect_back_or_to admin_place_path(@place.slug, anchor: "members"), notice: "Đã thu hồi mã mời."
  end

  private
    def set_place
      @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    end
end
