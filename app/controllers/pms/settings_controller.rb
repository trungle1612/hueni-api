# Cài đặt cơ sở (#244, owners): Tài khoản chuyển khoản (shown on Thu tiền) and the Dịch vụ catalog
# (Pms::ServicesController), same model rules as /admin's homestay page.
class Pms::SettingsController < Pms::BaseController
  before_action -> { authorize!(:manage, current_place) if current_place }

  def show
  end

  def bank
    raise ActiveRecord::RecordNotFound unless current_place
    if current_place.update(params.expect(place: %i[bank_name bank_account bank_holder]))
      redirect_to pms_settings_path, status: :see_other, flash: { toast: "Đã lưu tài khoản chuyển khoản" }
    else
      render :show, status: :unprocessable_entity
    end
  end
end
