# Tìm đặt phòng (#235): bookings of every homestay you are a member of, owner or staff (Booking.search_sections, as /admin/tim).
class Pms::SearchesController < Pms::BaseController
  def show
    @query = Booking.search_query(params[:q])
    return if @query.size < 2
    @sections = Current.user.accessible_bookings.includes(room: :place).search_sections(@query)
  end
end
