# Booking detail for the Mini App (#153): the booking, its payments and services, Tổng / Đã trả / Còn phải thu.
# Staff see the room total and what is due, not the nightly quote (like /admin Thanh toán).
class MiniApp::V1::BookingsController < MiniApp::V1::BaseController
  def show
    booking = Current.user.accessible_bookings.includes(:calendar_feed, :charges, room: :place, payments: :user).find(params[:id])
    @place = booking.room.place
    render json: booking_json(booking).merge(
      room_total: booking.room_total, total: booking.total, paid: booking.paid, due: booking.due,
      payments: booking.payments.sort_by(&:created_at).map { |payment|
        { id: payment.id, amount: payment.signed_amount, kind: payment.kind, method: payment.payment_method, note: payment.note, at: payment.created_at, by: payment.user&.name }
      },
      charges: booking.charges.sort_by(&:created_at).map { |charge|
        { id: charge.id, name: charge.name, unit: charge.unit, price: charge.unit_price, qty: charge.quantity, amount: charge.amount, at: charge.created_at }
      }
    )
  end
end
