# Dịch vụ on a booking (#154), like Admin::BookingChargesController: anyone at the desk adds one from the homestay's
# catalog (GET /places/:id/services) or removes it. Answers with the booking detail.
class MiniApp::V1::ChargesController < MiniApp::V1::BaseController
  before_action do
    @booking = Current.user.accessible_bookings.manual.find(params[:booking_id])
    @place = @booking.room.place
    authorize!(:operate, @place)
  end

  def create
    service = @place.services.find(params.expect(:service_id))
    charge = @booking.charges.build(name: service.name, unit_price: service.price, unit: service.unit, quantity: params[:quantity].presence || 1, user: Current.user)
    charge.save ? render_booking(@booking, status: :created) : render_invalid(charge)
  end

  def destroy
    @booking.charges.find(params[:id]).destroy!
    render_booking(@booking)
  end
end
