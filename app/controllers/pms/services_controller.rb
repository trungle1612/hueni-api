# Dịch vụ on Cài đặt cơ sở (#244), owners only, like Admin::ServicesController. Bookings that already have
# a service keep their copy (BookingCharge).
class Pms::ServicesController < Pms::BaseController
  before_action :set_service, only: %i[update destroy]

  def create
    place = current_place or raise ActiveRecord::RecordNotFound
    authorize!(:manage, place)
    save place.services.build(service_params), "Đã thêm"
  end

  def update
    @service.assign_attributes(service_params)
    save @service, "Đã lưu"
  end

  def destroy
    @service.destroy!
    redirect_to pms_settings_path, status: :see_other, flash: { toast: "Đã xoá dịch vụ #{@service.name}. Đặt phòng đã có dịch vụ này vẫn giữ nguyên." }
  end

  private
    def set_service
      @service = Service.where(place: Current.user.accessible_places).find(params[:id])
      authorize!(:manage, @service.place)
    end

    def service_params = params.expect(service: %i[name price unit])

    def save(service, message)
      if service.save
        redirect_to pms_settings_path, status: :see_other, flash: { toast: "#{message} dịch vụ #{service.name}" }
      else
        redirect_to pms_settings_path, status: :see_other, alert: service.errors.full_messages.to_sentence
      end
    end
end
