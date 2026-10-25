class Admin::DashboardController < Admin::BaseController
  def show
    @places = Current.user.accessible_places.order(:name)
    @vacancy = Vacancy.cached[:places]
    @active_rooms = Room.where(active: true, place_id: @places.select(:id)).group(:place_id).count
    @feed_errors = Current.user.accessible_calendar_feeds.where.not(last_error: nil)
      .joins(:room).group("rooms.place_id").count
    # Admins: every homestay's members and failing feeds (platform health), no homestay data.
    if Current.user.admin?
      @pending_registrations = RegistrationRequest.pending.count
      @all_places = Place.includes(place_memberships: :user).order(:name)
      @all_feed_errors = CalendarFeed.where.not(last_error: nil).joins(:room).group("rooms.place_id").count
    end
    rooms = Current.user.accessible_rooms
    @days_by_place = RoomDay.for(rooms.order(:name)).group_by { it.room.place_id }

    @open_rooms = @active_rooms.values.sum
    @tomorrow = params[:day] == "mai" # Ngày mai (#142): same lists for tomorrow, nothing to press yet
    today = Today.new(rooms, tomorrow: @tomorrow)
    @arrivals, @departures, @in_house, @dirty_rooms = today.arrivals, today.departures, today.in_house, today.dirty_rooms
    @issues = today.issues.map { [ it.kind, it.title, it.detail, issue_path(it) ] }
  end

  private
    # Cần xử lý links: a conflict opens the calendar at its day, a dirty room the homestay page,
    # a missing lưu trú the booking (iCal bookings have no edit page, so their calendar).
    def issue_path(issue)
      booking = issue.booking
      slug = booking.room.place.slug
      case issue.kind
      when :error then admin_place_calendar_path(slug, from: issue.date.iso8601)
      when :clean then admin_place_path(slug, anchor: helpers.dom_id(booking.room))
      when :stay then booking.manual? ? edit_admin_booking_path(booking) : admin_place_calendar_path(slug)
      end
    end
end
