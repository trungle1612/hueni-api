class Admin::DashboardController < Admin::BaseController
  # Hôm nay lists holds starting within this many days; the calendar has the rest.
  HOLDS_DAYS = 3

  def show
    @places = Current.user.accessible_places.order(:name)
    @vacancy = Vacancy.cached[:places]
    @active_rooms = Room.where(active: true, place_id: @places.select(:id)).group(:place_id).count
    @feed_errors = Current.user.accessible_calendar_feeds.where.not(last_error: nil)
      .joins(:room).group("rooms.place_id").count
    # Admins: every homestay's members and failing feeds (platform health), no homestay data.
    if Current.user.admin?
      @all_places = Place.includes(place_memberships: :user).order(:name)
      @all_feed_errors = CalendarFeed.where.not(last_error: nil).joins(:room).group("rooms.place_id").count
    end
    rooms = Current.user.accessible_rooms
    @days_by_place = RoomDay.for(rooms.order(:name)).group_by { it.room.place_id }

    today = Date.current
    bookings = Booking.where(room_id: rooms.select(:id)).includes(:calendar_feed, room: :place).order(:start_date, :id)
    @departures = bookings.in_house.where(end_date: ..today).to_a
    @dirty_rooms = rooms.dirty.includes(:place).order(:name).to_a
    @arrivals = bookings.blocking.not_checked_in.where(start_date: ..today, end_date: Booking.arrival_date.next_day..).to_a
    @in_house = bookings.in_house.where(end_date: today.next_day..).to_a
    @holds = bookings.hold.where(start_date: ..(today + HOLDS_DAYS), end_date: today.next_day..).to_a
  end
end
