# Cài đặt cơ sở (#244, owners): Tài khoản chuyển khoản (shown on Thu tiền), the Dịch vụ catalog
# (Pms::ServicesController), same model rules as the Mini App, and Đưa đón sân bay (#307).
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

  # Đưa đón sân bay (#306, #307): partner on/off, price per leg (snapshotted on each new leg), the driver's phone.
  def transfer
    raise ActiveRecord::RecordNotFound unless current_place
    if current_place.update(params.expect(place: %i[transfer_partner transfer_price driver_phone]))
      redirect_to pms_settings_path, status: :see_other, flash: { toast: "Đã lưu đưa đón sân bay" }
    else
      render :show, status: :unprocessable_entity
    end
  end
end
