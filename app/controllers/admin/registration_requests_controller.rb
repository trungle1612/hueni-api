# Owner registration requests (RegistrationsController). Admin only, like Người dùng: the admin calls the
# homestay's number on hueni to verify, then approves, which creates the account already linked to Zalo.
class Admin::RegistrationRequestsController < Admin::BaseController
  before_action :require_admin
  before_action :set_registration
  before_action :save_choices, only: %i[update approve reject]

  def show
    @places = Place.order(:name)
  end

  def update
    redirect_to admin_registration_request_path(@registration), notice: "Đã lưu."
  end

  def approve
    if params[:called] != "1"
      redirect_to admin_registration_request_path(@registration), alert: "Gọi xác nhận trước khi tạo tài khoản."
    elsif @registration.approve!(by: Current.user)
      redirect_to edit_admin_user_path(@registration.user),
        notice: "Đã tạo tài khoản cho #{@registration.name}. Hãy báo người này đăng nhập bằng Zalo."
    else
      redirect_to admin_registration_request_path(@registration), alert: @registration.errors[:base].to_sentence
    end
  end

  def reject
    if @registration.reject!(by: Current.user)
      redirect_to admin_users_path, notice: "Đã từ chối yêu cầu của #{@registration.name}."
    else
      redirect_to admin_registration_request_path(@registration), alert: @registration.errors[:base].to_sentence
    end
  end

  private
    def set_registration
      @registration = RegistrationRequest.find(params[:id])
    end

    # Lưu, Tạo tài khoản and Từ chối all submit the one form: keep the homestay and note first, then act.
    # Any homestay, like the Người dùng form: the admin needn't be a member of it.
    def save_choices
      return unless @registration.pending? && (choices = params[:registration_request])
      place = Place.find(choices[:place_id]) if choices[:place_id].present?
      @registration.update!(place:, admin_note: choices[:admin_note].presence)
    end
end
