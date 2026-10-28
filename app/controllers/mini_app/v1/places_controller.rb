# One homestay's rooms, Hôm nay, room board and calendar for the Mini App (#153). Owners and staff alike;
# staff get no prices (see the serializers' params[:manage]).
class MiniApp::V1::PlacesController < MiniApp::V1::BaseController
  CALENDAR_DAYS = 14
  MAX_CALENDAR_DAYS = 62

  before_action :set_place

  # By floor (rooms without one last), switched-off rooms last within it, like the homestay page.
  def rooms
    render json: { rooms: MiniApp::RoomSerializer.new(ordered_rooms, params: serializer_params) }
  end

  # Hôm nay, or Ngày mai with ?day=mai; Cần xử lý stays today's (Today).
  def today
    today = Today.new(@place.rooms, tomorrow: params[:day] == "mai")
    preload(today.arrivals + today.departures + today.in_house)
    render json: MiniApp::TodaySerializer.new(today, params: serializer_params)
  end

  # RoomDay.for: each room's state today with the booking in it and the next one.
  def board
    days = RoomDay.for(ordered_rooms)
    preload(days.flat_map { [ it.booking, it.next_booking ] }.compact)
    render json: { date: Date.current, days: MiniApp::RoomDaySerializer.new(days, params: serializer_params) }
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
    render json: {
      from:, to:,
      rooms: MiniApp::RoomSerializer.new(rooms, params: serializer_params),
      bookings: MiniApp::BookingSerializer.new(bookings, params: serializer_params),
      conflicts:,
      maintenance_conflicts: bookings.select(&:in_maintenance?).map(&:id)
    }
  end

  # The booking form's live "còn trống / trùng lịch" check: the same validations as saving (Booking#date_problems).
  # booking_id: the booking being edited, so it does not clash with itself. free_room_ids: other rooms free those nights.
  def availability
    room = @place.rooms.find(params.expect(:room_id))
    booking = Booking.new(room:, start_date: date_param(:start_date), end_date: date_param(:end_date), id: params[:booking_id].presence)
    problems = booking.date_problems
    free = if problems.any? && booking.start_date && booking.end_date&.after?(booking.start_date)
      @place.rooms.where(active: true).where.not(id: room.id).order(:name)
        .select { Booking.new(room: it, start_date: booking.start_date, end_date: booking.end_date).date_problems.empty? }
    end
    render json: { available: problems.empty?, problems:, free_room_ids: free.to_a.map(&:id) }
  end

  # Dịch vụ catalog, for adding services to a booking.
  def services
    render json: { services: MiniApp::ServiceSerializer.new(@place.services.order(:name)) }
  end

  private
    def set_place
      @place = Current.user.accessible_places.find(params[:id])
    end

    def ordered_rooms = @place.rooms.order(Arel.sql("floor IS NULL, floor"), active: :desc, name: :asc)

    # Today and RoomDay load the bookings; the serializer also reads their feed and payments.
    def preload(bookings)
      ActiveRecord::Associations::Preloader.new(records: bookings.uniq, associations: [ :calendar_feed, :payments ]).call
    end
end
