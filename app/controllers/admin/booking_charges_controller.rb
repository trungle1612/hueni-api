# Dịch vụ on a booking (#140): anyone at the desk adds one from the homestay's catalog or removes it.
class Admin::BookingChargesController < Admin::BaseController
  before_action do
    @booking = Current.user.accessible_bookings.manual.find(params[:booking_id])
    @place = @booking.room.place
    authorize!(:operate, @place)
  end

  def create
    service = @place.services.find(params.expect(:service_id))
    charge = @booking.charges.build(name: service.name, unit_price: service.price, unit: service.unit, quantity: params[:quantity].presence || 1, user: Current.user)
    charge.save ? back(notice: "Đã thêm #{charge.label}.") : back(alert: charge.errors.full_messages.to_sentence)
  end

  def destroy
    charge = @booking.charges.find(params[:id])
    charge.destroy!
    back notice: "Đã bỏ #{charge.label}."
  end

  private
    def back(**flash) = redirect_to(edit_admin_booking_path(@booking, anchor: "thanh-toan"), **flash)
end
