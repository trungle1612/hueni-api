# Tìm đặt phòng (#143): bookings of every homestay you are a member of, owner or staff.
class Admin::SearchesController < Admin::BaseController
  LIMIT = 30

  def show
    @places = Current.user.accessible_places.order(:name)
    @query = params[:q].to_s.squish.first(50)
    return if @query.empty?
    results = Current.user.accessible_bookings.search(@query).includes(:calendar_feed, room: :place).to_a
    @in_house = results.select { it.can_check_out? }.sort_by(&:end_date)
    @upcoming = results.select { it.confirmed? && !it.checked_in_at && it.end_date > Date.current }.sort_by(&:start_date)
    @past = (results - @in_house - @upcoming).sort_by { [ -it.start_date.jd, -it.id ] }.first(LIMIT)
  end
end
