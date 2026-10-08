# Admin only. No email yet: the admin sends each user a one-time link to set their own password (Zalo login later).
class Admin::UsersController < Admin::BaseController
  before_action :require_admin
  before_action :set_user, only: %i[edit update reset_password]

  def index
    @users = User.includes(place_memberships: :place).order(:role, :name)
  end

  def new
    @user = User.new(role: "user")
  end

  def create
    @user = User.new(user_params.merge(password: User.unknown_password))
    if save_with_memberships { @user.save }
      redirect_to edit_admin_user_path(@user), notice: "Đã tạo tài khoản.", flash: { setup_link: setup_link }
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if save_with_memberships { @user.update(user_params) }
      redirect_to admin_users_path, notice: "Đã lưu #{@user.name}."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Locks the old password and older links and logs the user out everywhere: a reset usually means a
  # forgotten password, a lost phone or a leaked one. Not for yourself: it would end your own session.
  def reset_password
    raise ActiveRecord::RecordNotFound if @user == Current.user
    @user.update!(password: User.unknown_password)
    @user.sessions.destroy_all
    redirect_to edit_admin_user_path(@user), notice: "Đã khoá mật khẩu cũ và đăng xuất #{@user.name} khỏi mọi thiết bị.",
      flash: { setup_link: setup_link }
  end

  private
    def require_admin
      raise ActiveRecord::RecordNotFound unless Current.user.admin?
    end

    def set_user
      @user = User.find(params[:id])
    end

    # Admins can't change their own role, or they could lock themselves out of this page.
    def user_params
      params.expect(user: @user == Current.user ? %i[name phone_number] : %i[name phone_number role])
    end

    def setup_link = password_setup_url(token: @user.generate_token_for(:password_setup))

    # Saves the user (block) and memberships[<place_id>] = "owner" | "staff" | "" together, or nothing.
    # The last-owner rule surfaces as a form error.
    def save_with_memberships
      User.transaction do
        yield or raise ActiveRecord::Rollback
        Place.find_each do |place| # admins assign every homestay, also ones they aren't a member of
          role = params.dig(:memberships, place.id.to_s).presence
          membership = @user.place_memberships.find_or_initialize_by(place:)
          if role then membership.update!(role:)
          elsif membership.persisted? then membership.destroy!
          end
        end
        true
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed => error
        @user.errors.add(:base, error.record.errors.full_messages.to_sentence)
        raise ActiveRecord::Rollback
      end
    end
end
