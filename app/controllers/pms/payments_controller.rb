# Thu tiền on Chi tiết đặt phòng (#231): anyone at the desk takes money, like Admin::PaymentsController. Refunds come
# only with Huỷ đặt phòng here; refund requests and deleting a wrong entry stay on /admin for now.
class Pms::PaymentsController < Pms::BaseController
  def create
    booking = Current.user.accessible_bookings.manual.find(params[:booking_id])
    authorize!(:operate, booking.room.place)
    payment = booking.payments.build(params.expect(payment: %i[amount payment_method note]).merge(kind: "payment", user: Current.user))
    if payment.save
      flash[:toast] = "Đã ghi nhận #{helpers.pms_money(payment.amount)} · #{payment.method_label}"
    else
      flash[:alert] = payment.errors.full_messages.to_sentence
    end
    redirect_to pms_booking_path(booking), status: :see_other
  end
end
