# Tìm đặt phòng (#143): bookings of every homestay you are a member of, owner or staff.
class Admin::SearchesController < Admin::BaseController
  LIMIT = 30

  def show
    @places = Current.user.accessible_places.order(:name)
    @query = params[:q].to_s.squish.first(50)
    return if @query.empty?
    @in_house, @upcoming, @past = Current.user.accessible_bookings.includes(:calendar_feed, room: :place).search_sections(@query, limit: LIMIT).values
  end
end
