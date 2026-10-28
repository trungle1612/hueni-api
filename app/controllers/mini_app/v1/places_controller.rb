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

  # Hôm nay, or Ngày mai with ?day=mai; Cần xử lý stays today's (Today). feed_errors: Lỗi đồng bộ (n), OTA feeds failing now.
  def today
    today = Today.new(@place.rooms, tomorrow: params[:day] == "mai")
    preload(today.arrivals + today.departures + today.in_house)
    render json: MiniApp::TodaySerializer.new(today, params: serializer_params).serializable_hash.merge(feed_errors: feeds.where.not(last_error: nil).count)
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

  # Báo cáo, owners only: ?month=YYYY-MM (default this month) or ?period=7d. report.csv = Xuất CSV.
  def report
    authorize!(:manage, @place)
    report = params[:period] == "7d" ? Report.week(@place) : Report.new(@place, month_param || Date.current)
    if request.format.csv?
      send_data report.to_csv, type: "text/csv; charset=utf-8", filename: "bao-cao-#{@place.slug}-#{report.first.iso8601}-#{report.last.iso8601}.csv"
    else
      render json: MiniApp::ReportSerializer.new(report, params: serializer_params)
    end
  end

  # Tìm đặt phòng in this homestay: guest name (no diacritics needed), phone digits or DP code (Booking.search).
  # q comes in the body so guest names never sit in a URL; it is filtered from the logs.
  def search
    query = params[:q].to_s.squish.first(50)
    sections = query.empty? ? { in_house: [], upcoming: [], past: [] } :
      Booking.where(room: @place.rooms).includes(:calendar_feed, :payments).search_sections(query, limit: Admin::SearchesController::LIMIT)
    render json: sections.transform_values { MiniApp::BookingSerializer.new(it, params: serializer_params) }
  end

  # Kênh OTA (#157): every room with its feeds, rooms with a failing feed first. Read-only; Đồng bộ ngay is per feed.
  def calendar_feeds
    rooms = @place.rooms.includes(:calendar_feeds).sort_by { [ it.calendar_feeds.any?(&:last_error) ? 0 : 1, it.name ] }
    render json: { rooms: MiniApp::RoomFeedsSerializer.new(rooms) }
  end

  private
    def feeds = CalendarFeed.where(room: @place.rooms)

    def set_place
      @place = Current.user.accessible_places.find(params[:id])
    end

    # A YYYY-MM query param, or nil when missing or malformed.
    def month_param
      Date.strptime(params[:month].to_s, "%Y-%m") if params[:month].is_a?(String)
    rescue Date::Error
      nil
    end

    def ordered_rooms = @place.rooms.order(Arel.sql("floor IS NULL, floor"), active: :desc, name: :asc)

    # Today and RoomDay load the bookings; the serializer also reads their feed and payments.
    def preload(bookings)
      ActiveRecord::Associations::Preloader.new(records: bookings.uniq, associations: [ :calendar_feed, :payments ]).call
    end
end
