# Mã mời (#211), admins only (like Người dùng): a code for any homestay, with its role, uses and days.
# Whoever enters it in the Mini App with an unknown Zalo joins that homestay (Invite.redeem).
class Admin::InvitesController < Admin::BaseController
  before_action :require_admin

  def index
    @invites = Invite.usable.includes(:place).order(:id)
    @places = Place.order(:name)
  end

  def create
    attrs = params.expect(invite: %i[place_id role max_uses days])
    invite = Place.find(attrs[:place_id]).invites.build(role: attrs[:role], max_uses: attrs[:max_uses],
      expires_at: attrs[:days].to_i.clamp(1, 30).days.from_now, created_by: Current.user) # admins assign every homestay
    if invite.save
      redirect_to admin_invites_path, notice: "Đã tạo mã mời #{invite.display_code} cho #{invite.place.name}."
    else
      redirect_to admin_invites_path, alert: invite.errors.full_messages.to_sentence
    end
  end

  def destroy
    Invite.find(params[:id]).destroy!
    redirect_to admin_invites_path, notice: "Đã thu hồi mã mời."
  end
end
