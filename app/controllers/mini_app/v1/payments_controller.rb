# Thanh toán (#154), like Admin::PaymentsController: anyone at the desk takes money; refunds need the refund right
# (owners, staff given it, #168; others send a refund request); deleting a wrong entry is owners only. Answers with the booking detail.
class MiniApp::V1::PaymentsController < MiniApp::V1::BaseController
  before_action do
    @booking = Current.user.accessible_bookings.manual.find(params[:booking_id])
    @place = @booking.room.place
  end

  def create
    payment = @booking.payments.build(params.expect(payment: %i[amount payment_method kind note]).merge(user: Current.user))
    authorize!(payment.refund? ? :refund : :operate, @place)
    payment.save ? render_booking(@booking, status: :created) : render_invalid(payment)
  end

  def destroy
    authorize!(:manage, @place)
    @booking.payments.find(params[:id]).destroy!
    render_booking(@booking)
  end
end
