# Thanh toán (#139) on the booking page. Anyone at the desk takes money; refunds and deleting a wrong entry are owners only.
class Admin::PaymentsController < Admin::BaseController
  before_action do
    @booking = Current.user.accessible_bookings.manual.find(params[:booking_id])
    @place = @booking.room.place
  end

  def create
    payment = @booking.payments.build(params.expect(payment: %i[amount payment_method kind note]).merge(user: Current.user))
    authorize!(payment.refund? ? :refund : :operate, @place)
    if payment.save
      back notice: "#{payment.refund? ? "Đã hoàn" : "Đã thu"} #{helpers.vnd(payment.amount)} · #{payment.method_label}."
    else
      back alert: payment.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize!(:manage, @place)
    payment = @booking.payments.find(params[:id])
    payment.destroy!
    back notice: "Đã xoá khoản #{payment.refund? ? "hoàn" : "thu"} #{helpers.vnd(payment.amount)}."
  end

  private
    def back(**flash) = redirect_to(edit_admin_booking_path(@booking, anchor: "thanh-toan"), **flash)
end
