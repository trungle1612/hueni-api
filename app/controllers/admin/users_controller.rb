# Admin only. No email yet: passwords are generated here and the admin sends them to the owner (Zalo login later).
class Admin::UsersController < Admin::BaseController
  before_action :require_admin
  before_action :set_user, only: %i[edit update reset_password]

  def index
    @users = User.includes(:places).order(:role, :name)
  end

  def new
    @user = User.new(role: "owner")
  end

  def create
    @user = User.new(user_params.merge(password: User.generate_password))
    @user.places = selected_places
    if @user.save
      redirect_to edit_admin_user_path(@user), notice: "Đã tạo tài khoản.", flash: { new_password: @user.password }
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

  # Also logs the user out everywhere: a reset usually means a lost phone or a leaked password.
  # Not for yourself: your own session would end before you could read the new password.
  def reset_password
    raise ActiveRecord::RecordNotFound if @user == Current.user
    password = User.generate_password
    @user.update!(password:)
    @user.sessions.destroy_all
    redirect_to edit_admin_user_path(@user), notice: "Đã tạo mật khẩu mới và đăng xuất #{@user.name} khỏi mọi thiết bị.",
      flash: { new_password: password }
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

    def selected_places
      Current.user.accessible_places.where(id: params.dig(:user, :place_ids))
    end
end
