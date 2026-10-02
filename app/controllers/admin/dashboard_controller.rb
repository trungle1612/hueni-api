class Admin::DashboardController < Admin::BaseController
  def show
    @places = Current.user.accessible_places.order(:name)
    @vacancy = Vacancy.cached[:places]
    @active_rooms = Room.where(active: true, place_id: @places.select(:id)).group(:place_id).count
    @feed_errors = Current.user.accessible_calendar_feeds.where.not(last_error: nil)
      .joins(:room).group("rooms.place_id").count
  end
end
