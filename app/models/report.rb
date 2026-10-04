# One homestay, one calendar month: occupancy, estimated revenue and booking activity for owners (#77).
# A night is a date slept (end_date exclusive). Nights sold follow Booking#occupied_until, like vacancy.
# Revenue is an estimate: nights × the room's current price; unpriced rooms are left out of revenue, ADR and RevPAR.
class Report
  CHANNEL_LABELS = { "manual" => "Trực tiếp" }.merge(CalendarFeed::PROVIDER_LABELS).freeze

  RoomRow = Data.define(:room, :sold, :held) do
    def revenue = room.price && sold * room.price
  end

  attr_reader :place, :month

  def initialize(place, month)
    @place = place
    @month = month.beginning_of_month
  end

  def days = month.end_of_month.day
  def previous = Report.new(place, month.prev_month)

  # Active rooms, plus inactive ones that sold nights this month.
  def rooms
    @rooms ||= place.rooms.order(:name).map { |room|
      stays = stays_by_room.fetch(room.id, [])
      RoomRow.new(room:, sold: nights(stays.select(&:confirmed?)), held: nights(stays.select(&:hold?)))
    }.select { it.room.active? || it.sold.positive? }
  end

  def sold = rooms.sum(&:sold)
  def held = rooms.sum(&:held)
  def available = rooms.size * days
  def occupancy = ratio(sold, available)

  def revenue = priced.sum(&:revenue)
  def adr = ratio(revenue, priced.sum(&:sold))
  def revpar = ratio(revenue, priced.size * days)
  def unpriced_rooms? = priced.size < rooms.size

  # { "manual" => { nights:, bookings:, revenue: }, "airbnb" => ... }: channels with any night or booking.
  def channels
    @channels ||= begin
      sold_stays = stays.select(&:confirmed?).group_by { channel(it) }
      arrivals_by = arrivals.group_by { channel(it) }
      CHANNEL_LABELS.keys.filter_map do |key|
        next unless sold_stays[key] || arrivals_by[key]
        list = sold_stays.fetch(key, [])
        [ key, { nights: nights(list), bookings: arrivals_by.fetch(key, []).size,
                 revenue: list.sum { it.room.price ? nights([ it ]) * it.room.price : 0 } } ]
      end.to_h
    end
  end

  def booking_count = arrivals.size
  def outcomes = %w[confirmed hold cancelled].index_with { |status| arrivals.count { it.status == status } }
  def alos = ratio(arrivals.select(&:confirmed?).sum { (it.end_date - it.start_date).to_i }, outcomes["confirmed"])

  # iCal bookings the sync deleted (the OTA cancelled them), by their start_date in the activity log.
  def ota_cancelled
    @ota_cancelled ||= PaperTrail::Version.where(place_id: place.id, item_type: "Booking", event: "destroy")
      .where("json_extract(object, '$.source') = 'ical'")
      .where("json_extract(object, '$.start_date') BETWEEN ? AND ?", month.iso8601, month.end_of_month.iso8601).count
  end

  def cancellation_rate = ratio(outcomes["cancelled"] + ota_cancelled, booking_count + ota_cancelled)

  private
    def range = month..month.end_of_month

    def stays
      @stays ||= Booking.where(room_id: place.rooms.select(:id)).occupying(month, month.next_month)
        .includes(:room, :calendar_feed).to_a
    end

    def stays_by_room = @stays_by_room ||= stays.group_by(&:room_id)

    def arrivals
      @arrivals ||= Booking.where(room_id: place.rooms.select(:id), start_date: range).includes(:calendar_feed).to_a
    end

    def priced = rooms.select { it.room.price }

    # Nights of these bookings inside the month.
    def nights(bookings)
      bookings.sum { [ [ it.occupied_until, month.next_month ].min - [ it.start_date, month ].max, 0 ].max.to_i }
    end

    def channel(booking) = booking.manual? ? "manual" : booking.calendar_feed&.provider || "other"

    def ratio(part, whole) = whole.zero? ? nil : part.to_f / whole
end
