# One homestay's rooms, Hôm nay, room board and calendar for the Mini App (#153). Owners and staff alike;
# staff get no prices (see BaseController#room_json / #booking_json).
class MiniApp::V1::PlacesController < MiniApp::V1::BaseController
  CALENDAR_DAYS = 14
  MAX_CALENDAR_DAYS = 62

  before_action :set_place

  # By floor (rooms without one last), switched-off rooms last within it, like the homestay page.
  def rooms
    render json: { rooms: ordered_rooms.map { room_json(it) } }
  end

  # Hôm nay, or Ngày mai with ?day=mai; Cần xử lý stays today's (Today).
  def today
    tomorrow = params[:day] == "mai"
    today = Today.new(@place.rooms, tomorrow:)
    preload(today.arrivals + today.departures + today.in_house + today.issues.map(&:booking))
    render json: {
      date: tomorrow ? Date.current.next_day : Date.current,
      arrivals: today.arrivals.map { booking_json(it) },
      departures: today.departures.map { booking_json(it) },
      in_house: today.in_house.map { booking_json(it) },
      dirty_rooms: today.dirty_rooms.map { room_json(it) },
      issues: today.issues.map { { kind: it.kind, title: it.title, detail: it.detail, booking_id: it.booking.id, date: it.date } }
    }
  end

  # RoomDay.for: each room's state today with the booking in it and the next one.
  def board
    days = RoomDay.for(ordered_rooms)
    preload(days.flat_map { [ it.booking, it.next_booking ] }.compact)
    render json: { date: Date.current, days: days.map { |day|
      { room: room_json(day.room), state: day.state, booking: day.booking && booking_json(day.booking), next: day.next_booking && booking_json(day.next_booking) }
    } }
  end

  # Active rooms × [from, to) (default 14 days, at most 62), like /admin calendar: confirmed bookings in the range
  # plus guests still in, OTA conflicts and bookings caught by a Bảo trì.
  def calendar
    from = date_param(:from) || Date.current
    to = (date_param(:to) || from + CALENDAR_DAYS).clamp(from.next_day, from + MAX_CALENDAR_DAYS)
    rooms = @place.rooms.where(active: true).order(:name).to_a
    bookings = Booking.blocking.where(room: rooms).merge(Booking.overlapping(from, to).or(Booking.in_house))
      .includes(:calendar_feed, :room, :payments).order(:start_date, :id).to_a
    conflicts = bookings.select(&:ical?).flat_map do |ical|
      bookings.select { it.manual? && it.room_id == ical.room_id && it.overlaps?(ical) }.map { { ota_id: ical.id, manual_id: it.id } }
    end
    render json: { from:, to:, rooms: rooms.map { room_json(it) }, bookings: bookings.map { booking_json(it) }, conflicts:,
                   maintenance_conflicts: bookings.select(&:in_maintenance?).map(&:id) }
  end

  private
    def set_place
      @place = Current.user.accessible_places.find_by!(slug: params[:slug])
    end

    def ordered_rooms = @place.rooms.order(Arel.sql("floor IS NULL, floor"), active: :desc, name: :asc)

    def preload(bookings)
      ActiveRecord::Associations::Preloader.new(records: bookings.uniq, associations: [ :calendar_feed, :payments ]).call
    end
end
