# Thu tiền and Hoàn tiền on Chi tiết đặt phòng (#231, #247): anyone at the desk takes money, a refund needs the refund
# right (staff without it send a RefundRequest instead), deleting a wrong entry is for owners. A cancelled booking only refunds.
class Pms::PaymentsController < Pms::BaseController
  before_action do
    @booking = Current.user.accessible_bookings.manual.find(params[:booking_id])
    @place = @booking.room.place
  end

  def create
    payment = @booking.payments.build(params.expect(payment: %i[amount payment_method kind note]).merge(user: Current.user))
    authorize!(payment.refund? ? :refund : :operate, @place)
    if payment.save
      flash[:toast] = "#{payment.refund? ? "Đã hoàn" : "Đã ghi nhận"} #{helpers.pms_money(payment.amount)} · #{payment.method_label}"
    else
      flash[:alert] = payment.errors.full_messages.to_sentence
    end
    redirect_to pms_booking_path(@booking), status: :see_other
  end

  def destroy
    authorize!(:manage, @place)
    payment = @booking.payments.find(params[:id])
    payment.destroy!
    redirect_to pms_booking_path(@booking), status: :see_other, flash: { toast: "Đã xoá khoản #{payment.refund? ? "hoàn" : "thu"} #{helpers.pms_money(payment.amount)}" }
  end
end
