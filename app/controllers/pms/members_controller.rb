# Nhân viên (#245, ADR-001), owners only: members with role and Quyền thêm, Mời nhân viên (a one-time Zalo link),
# lock / unlock, remove, leave, a new link; Chờ duyệt refund requests on top. Same model rules as /admin and the Mini App.
class Pms::MembersController < Pms::BaseController
  before_action :set_membership, except: %i[index create]
  before_action -> { authorize!(:manage, @place) }, except: %i[index create]

  def index
    return unless current_place
    authorize!(:manage, @place = current_place)
    @memberships = @place.place_memberships.includes(user: %i[api_tokens sessions]).sort_by { [ it.owner? ? 0 : 1, it.user.name ] }
    @requests = RefundRequest.pending_at(@place).includes(:requested_by, booking: :room)
    @new_membership ||= @place.place_memberships.build(role: "staff", user: User.new)
  end

  def create
    @place = current_place or raise ActiveRecord::RecordNotFound
    authorize!(:manage, @place)
    membership = PlaceMembership.add(@place, **params.expect(member: [ :name, :phone_number, :role, permissions: [] ]).to_h.symbolize_keys)
    return with_link(membership.user, "Đã thêm #{membership.user.name}") if membership.persisted?
    @new_membership = membership
    index
    render :index, status: :unprocessable_entity
  end

  def update
    if @membership.update(params.expect(member: [ :role, permissions: [] ]))
      flash[:toast] = "Đã lưu quyền của #{@membership.user.name}"
    else
      flash[:alert] = @membership.errors.full_messages.to_sentence
    end
    back
  end

  # Xoá khỏi cơ sở, or Rời cơ sở for yourself; the model keeps at least one owner.
  def destroy
    name = @membership.user.name
    if !@membership.destroy then flash[:alert] = @membership.errors.full_messages.to_sentence
    elsif @membership.user == Current.user then return redirect_to(pms_today_path, status: :see_other, flash: { toast: "Bạn đã rời #{@place.name}" })
    else flash[:toast] = "Đã xoá #{name} khỏi cơ sở"
    end
    back
  end

  def lock
    if @membership.lock
      flash[:toast] = "Đã khoá #{@membership.user.name}"
    else
      flash[:alert] = @membership.errors.full_messages.to_sentence
    end
    back
  end

  def unlock
    @membership.update!(locked_at: nil)
    flash[:toast] = "Đã mở khoá #{@membership.user.name}"
    back
  end

  # Tạo link liên kết mới (User#reset_login!): the old link and every login of theirs end.
  def setup_link
    user = @membership.user
    raise Forbidden unless user.login_link_by?(Current.user)
    user.reset_login!
    with_link(user, "Đã huỷ liên kết cũ của #{user.name}")
  end

  private
    def set_membership
      @membership = PlaceMembership.where(place: Current.user.accessible_places).find(params[:id])
      @place = @membership.place
    end

    # Stepping down to staff leaves this owners-only page.
    def back = redirect_to(allowed_to?(:manage, @place) ? pms_members_path : pms_more_path, status: :see_other)

    # The link is shown once, in the sheet that opens after the redirect.
    def with_link(user, toast)
      redirect_to pms_members_path, status: :see_other,
        flash: { toast:, setup_link: { "name" => user.name, "url" => password_setup_url(token: user.generate_token_for(:password_setup)) } }
    end
end
