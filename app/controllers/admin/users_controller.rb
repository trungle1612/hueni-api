# Admin only. No email yet: the admin sends each user a one-time link to set their own password (Zalo login later).
class Admin::UsersController < Admin::BaseController
  before_action :require_admin
  before_action :set_user, only: %i[edit update reset_password]

  def index
    @users = User.includes(:places).order(:role, :name)
  end

  def new
    @user = User.new(role: "user")
  end

  def create
    @user = User.new(user_params.merge(password: User.unknown_password))
    @user.places = selected_places
    if @user.save
      redirect_to edit_admin_user_path(@user), notice: "Đã tạo tài khoản.", flash: { setup_link: setup_link }
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    saved = User.transaction do
      @user.places = selected_places
      @user.update(user_params) or raise ActiveRecord::Rollback
    end
    if saved
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

    def selected_places
      Current.user.accessible_places.where(id: params.dig(:user, :place_ids))
    end
end
