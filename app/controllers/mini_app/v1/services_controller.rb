# Dịch vụ catalog (#162), like Admin::ServicesController: owners only. Listing it (GET /places/:id/services) is staff too.
class MiniApp::V1::ServicesController < MiniApp::V1::BaseController
  def create
    @place = Current.user.accessible_places.find(params[:place_id])
    authorize!(:manage, @place)
    service = @place.services.build(service_params)
    service.save ? render(json: MiniApp::ServiceSerializer.new(service), status: :created) : render_invalid(service)
  end

  def update
    service = find_service
    service.update(service_params) ? render(json: MiniApp::ServiceSerializer.new(service)) : render_invalid(service)
  end

  # Bookings that already have it keep their copy (BookingCharge).
  def destroy
    find_service.destroy!
    head :no_content
  end

  private
    def find_service
      service = Service.where(place: Current.user.accessible_places).find(params[:id])
      authorize!(:manage, @place = service.place)
      service
    end

    def service_params = params.expect(service: %i[name price unit])
end
