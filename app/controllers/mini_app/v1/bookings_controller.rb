# Booking detail for the Mini App (#153): the booking, its payments and services, Tổng / Đã trả / Còn phải thu.
class MiniApp::V1::BookingsController < MiniApp::V1::BaseController
  def show
    booking = Current.user.accessible_bookings.includes(:calendar_feed, :charges, room: :place, payments: :user).find(params[:id])
    @place = booking.room.place
    render json: MiniApp::BookingDetailSerializer.new(booking, params: serializer_params)
  end
end
