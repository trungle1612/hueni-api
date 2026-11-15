# Tìm đặt phòng (#143): bookings of every homestay you are a member of, owner or staff.
class Admin::SearchesController < Admin::BaseController
  def show
    @places = Current.user.accessible_places.order(:name)
    @query = Booking.search_query(params[:q])
    return if @query.empty?
    @in_house, @upcoming, @past = Current.user.accessible_bookings.includes(:calendar_feed, room: :place).search_sections(@query).values
  end
end
