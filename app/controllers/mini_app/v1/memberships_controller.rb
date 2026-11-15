# Nhân viên (#168, ADR-001), owners only: invite, role and Quyền thêm, lock / unlock, remove, a new login link.
# Like Admin::MembersController. :id is a PlaceMembership. Changes are in Hoạt động.
class MiniApp::V1::MembershipsController < MiniApp::V1::BaseController
  before_action :set_place, only: %i[index create]
  before_action :set_membership, except: %i[index create]
  before_action -> { authorize!(:manage, @place) }

  # Owners first; invited = has not linked Zalo yet; last_active_at = last use of the app or the web.
  def index
    memberships = @place.place_memberships.includes(user: %i[api_tokens sessions]).sort_by { [ it.owner? ? 0 : 1, it.user.name ] }
    render json: { members: memberships.map { member_json(it) } }
  end

  # { member: { name, phone_number, role, permissions } } → the member and the one-time link to send over Zalo.
  def create
    attrs = params.expect(member: [ :name, :phone_number, :role, permissions: [] ])
    @membership = PlaceMembership.add(@place, **attrs.to_h.symbolize_keys)
    user = @membership.user
    return render_invalid(user.errors.any? ? user : @membership) unless @membership.persisted?
    render json: { member: member_json(@membership), setup_link: setup_link_for(user) }, status: :created
  end

  # { member: { role, permissions } }
  def update
    @membership.update(params.expect(member: [ :role, permissions: [] ])) ? render_member : render_invalid(@membership)
  end

  def destroy
    @membership.destroy ? head(:no_content) : render_invalid(@membership)
  end

  # Khoá tài khoản: out of this homestay and logged out everywhere. Mở khoá: back in (they log in again).
  def lock
    @membership.lock ? render_member : render_invalid(@membership)
  end

  def unlock = @membership.update(locked_at: nil) ? render_member : render_invalid(@membership)

  # Tạo link liên kết Zalo (User#reset_login!), only for someone whose every homestay is yours, never yourself.
  def setup_link
    user = @membership.user
    raise Forbidden unless user.login_link_by?(Current.user)
    user.reset_login!
    render json: { member: member_json(@membership.reload), setup_link: setup_link_for(user) }
  end

  private
    def set_place
      @place = Current.user.accessible_places.find(params[:place_id])
    end

    def set_membership
      @membership = PlaceMembership.where(place: Current.user.accessible_places).find(params[:id])
      @place = @membership.place
    end

    def member_json(membership)
      user = membership.user
      { id: membership.id, user_id: user.id, name: user.name, phone: user.phone_number, role: membership.role,
        permissions: membership.owner? ? PlaceMembership::PERMISSIONS.keys : membership.permissions,
        locked: membership.locked?, invited: user.zalo_id.nil? && !user.admin?,
        last_active_at: user.last_active_at }
    end

    def render_member = render(json: { member: member_json(@membership.reload) })

    def setup_link_for(user) = password_setup_url(token: user.generate_token_for(:password_setup))
end
