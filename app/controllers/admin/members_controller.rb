# Owners manage who works at their homestay (admins do it from Người dùng). :id is a PlaceMembership.
class Admin::MembersController < Admin::BaseController
  before_action :set_place
  before_action -> { authorize!(:manage, @place) }
  before_action :set_membership, only: %i[edit update destroy setup_link]
  helper_method :can_send_link?

  def new
    @user = User.new
    @membership = @place.place_memberships.build(role: "staff")
  end

  def create
    @membership = PlaceMembership.add(@place, **params.expect(member: %i[name phone_number role]).to_h.symbolize_keys)
    @user = @membership.user
    if @membership.persisted?
      redirect_to edit_admin_place_member_path(@place.slug, @membership), notice: "Đã thêm #{@user.name}.", flash: { setup_link: setup_link_for(@user) }
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  # Redirects to the homestay page, which you can still open after stepping down to staff.
  def update
    if @membership.update(params.expect(place_membership: [ :role ]))
      redirect_to admin_place_path(@place.slug), notice: "Đã lưu vai trò của #{@membership.user.name}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if !@membership.destroy
      redirect_to admin_place_path(@place.slug), alert: @membership.errors.full_messages.to_sentence
    elsif @membership.user == Current.user
      redirect_to admin_root_path, notice: "Bạn đã rời #{@place.name}."
    else
      redirect_to admin_place_path(@place.slug), notice: "Đã xoá #{@membership.user.name} khỏi #{@place.name}."
    end
  end

  # Same as the admin reset (#23, User#reset_login!): a new Zalo link.
  def setup_link
    user = @membership.user
    raise Forbidden unless user.login_link_by?(Current.user)
    user.reset_login!
    redirect_to edit_admin_place_member_path(@place.slug, @membership),
      notice: "Đã huỷ liên kết Zalo cũ và đăng xuất #{user.name} khỏi mọi thiết bị.", flash: { setup_link: setup_link_for(user) }
  end

  private
    def set_place
      @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    end

    def set_membership
      @membership = @place.place_memberships.find(params[:id])
    end

    def can_send_link?(user) = user.login_link_by?(Current.user)

    def setup_link_for(user) = password_setup_url(token: user.generate_token_for(:password_setup))
end
