# Dịch vụ (#140): owners manage their homestay's catalog on the homestay page.
class Admin::ServicesController < Admin::BaseController
  before_action do
    @place = Current.user.accessible_places.find_by!(slug: params[:place_slug])
    authorize!(:manage, @place)
  end
  before_action -> { @service = @place.services.find(params[:id]) }, only: %i[update destroy]

  def create
    save @place.services.build(service_params), "Đã thêm"
  end

  def update
    @service.assign_attributes(service_params)
    save @service, "Đã lưu"
  end

  def destroy
    @service.destroy!
    back notice: "Đã xoá dịch vụ #{@service.name}. Đặt phòng đã có dịch vụ này vẫn giữ nguyên."
  end

  private
    def service_params = params.expect(service: %i[name price unit])

    def save(service, message)
      service.save ? back(notice: "#{message} dịch vụ #{service.name}.") : back(alert: service.errors.full_messages.to_sentence)
    end

    def back(**flash) = redirect_to(admin_place_path(@place.slug, anchor: "dich-vu"), **flash)
end
