# Owners manage who works at their homestay (admins do it from Người dùng). :id is a PlaceMembership.
class Admin::MembersController < Admin::BaseController
  PHONE_TAKEN = "Số điện thoại này đã được dùng. Nhờ quản trị viên thêm vào homestay.".freeze

  before_action :set_place
  before_action -> { authorize!(:manage, @place) }
  before_action :set_membership, only: %i[edit update destroy setup_link]
  helper_method :can_send_link?

  def new
    @user = User.new
    @membership = @place.place_memberships.build(role: "staff")
  end

  def create
    attrs = params.expect(member: %i[name phone_number role])
    @user = User.new(name: attrs[:name], phone_number: attrs[:phone_number], role: "user", password: User.unknown_password)
    @membership = @place.place_memberships.build(user: @user, role: attrs[:role])
    # Doesn't say whose number it is; linking an existing account stays an admin task.
    if @user.phone_number.present? && User.exists?(phone_number: @user.phone_number)
      @user.errors.add(:base, PHONE_TAKEN)
      return render :new, status: :unprocessable_entity
    end
    saved = User.transaction { (@user.save && @membership.save) or raise ActiveRecord::Rollback }
    if saved
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

  # Same as the admin reset (#23): locks the old password and older links, logs out everywhere.
  def setup_link
    user = @membership.user
    raise Forbidden unless can_send_link?(user)
    user.update!(password: User.unknown_password)
    user.sessions.destroy_all
    redirect_to edit_admin_place_member_path(@place.slug, @membership),
      notice: "Đã khoá mật khẩu cũ và đăng xuất #{user.name} khỏi mọi thiết bị.", flash: { setup_link: setup_link_for(user) }
  end

  private
    def set_place
      @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    end

    def set_membership
      @membership = @place.place_memberships.find(params[:id])
    end

    # Only for people whose every homestay is one you own: otherwise you could take over
    # another owner's member. Never yourself (ends your session) or an admin.
    def can_send_link?(user)
      user != Current.user && !user.admin? &&
        user.place_memberships.includes(:place).all? { Current.user.allowed_to?(:manage, it.place) }
    end

    def setup_link_for(user) = password_setup_url(token: user.generate_token_for(:password_setup))
end
