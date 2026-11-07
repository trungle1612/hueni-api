# Mã mời (#211), owners only: staff codes for their homestay (7 days, one use), the ones still usable, Thu hồi.
# Owner codes are admin-only (bin/rails invites:create).
class MiniApp::V1::InvitesController < MiniApp::V1::BaseController
  before_action :set_place, only: %i[index create]
  before_action :set_invite, only: :destroy
  before_action -> { authorize!(:manage, @place) }

  def index = render(json: { invites: @place.invites.usable.order(:id).map { invite_json(it) } })

  def create
    invite = @place.invites.create!(role: "staff", created_by: Current.user)
    render json: { invite: invite_json(invite) }, status: :created
  end

  def destroy
    @invite.destroy!
    head :no_content
  end

  private
    def set_place
      @place = Current.user.accessible_places.find(params[:place_id])
    end

    def set_invite
      @invite = Invite.where(place: Current.user.accessible_places).find(params[:id])
      @place = @invite.place
    end

    def invite_json(invite)
      { id: invite.id, code: invite.display_code, role: invite.role, expires_at: invite.expires_at,
        uses_left: invite.max_uses - invite.uses_count }
    end
end
