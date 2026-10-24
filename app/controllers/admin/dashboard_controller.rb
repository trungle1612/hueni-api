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

    today = Date.current
    bookings = Booking.where(room_id: rooms.select(:id)).includes(:calendar_feed, room: :place).order(:start_date, :id)
    @departures = bookings.in_house.where(end_date: ..today).to_a
    @dirty_rooms = rooms.dirty.includes(:place).order(:name).to_a
    @arrivals = bookings.blocking.not_checked_in.where(start_date: ..today, end_date: Booking.arrival_date.next_day..).to_a
    @in_house = bookings.in_house.where(end_date: today.next_day..).to_a
    @open_rooms = @active_rooms.values.sum
    @issues = issues(bookings)

    # Ngày mai (#142): who arrives, who leaves (their rooms Sẽ cần dọn), who stays on. Nothing to press yet.
    @tomorrow = params[:day] == "mai"
    return unless @tomorrow
    tomorrow = today.next_day
    @arrivals = bookings.blocking.not_checked_in.where(start_date: tomorrow).to_a
    @departures = bookings.blocking.where(checked_out_at: nil, end_date: tomorrow).to_a
    @dirty_rooms = @departures.map(&:room).uniq.sort_by(&:name)
    @in_house = bookings.blocking_on(tomorrow).where(start_date: ...tomorrow).to_a
  end

  private
    # Cần xử lý: [kind, what, who, link] for OTA conflicts from today on, guests arriving today to a dirty room,
    # and guests in without lưu trú.
    def issues(bookings)
      upcoming = bookings.blocking.where(end_date: Date.current.next_day..).to_a
      conflicts = upcoming.select(&:ical?).flat_map do |ical|
        upcoming.select { it.manual? && it.room_id == ical.room_id && it.overlaps?(ical) }.map do |manual|
          [ :error, "Trùng lịch OTA", "#{ical.label} và #{manual.label} · Phòng #{manual.room.name} · #{[ ical.start_date, manual.start_date ].max.strftime("%d/%m")}",
            admin_place_calendar_path(manual.room.place.slug, from: [ ical.start_date, manual.start_date ].max.iso8601) ]
        end
      end
      dirty = @arrivals.select { it.room.dirty? }.map do |booking|
        [ :clean, "Khách đến, phòng chưa dọn", "#{booking.label} · Phòng #{booking.room.name}", admin_place_path(booking.room.place.slug, anchor: helpers.dom_id(booking.room)) ]
      end
      undeclared = (@departures + @in_house).select(&:needs_declaration?).map do |booking|
        [ :stay, "Chưa khai báo lưu trú", "#{booking.label} · Phòng #{booking.room.name}",
          booking.manual? ? edit_admin_booking_path(booking) : admin_place_calendar_path(booking.room.place.slug) ]
      end
      conflicts + dirty + undeclared
    end
end
