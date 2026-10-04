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
      sold = sold_nights.fetch(room.id, {})
      held = stays.select { it.hold? && it.room_id == room.id }.flat_map { dates(it) }.uniq - sold.keys
      RoomRow.new(room:, sold: sold.size, held: held.size)
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
      sold_by = sold_nights.values.flat_map(&:values).group_by { channel(it) }
      arrivals_by = arrivals.group_by { channel(it) }
      CHANNEL_LABELS.keys.filter_map do |key|
        next unless sold_by[key] || arrivals_by[key]
        nights = sold_by.fetch(key, []) # one booking per night it sold
        [ key, { nights: nights.size, bookings: arrivals_by.fetch(key, []).size, revenue: nights.sum { it.room.price || 0 } } ]
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

    # { room_id => { date => the confirmed booking that sold that night } }. A night shared by an iCal and a manual
    # booking (a calendar conflict) is sold once, to the OTA.
    def sold_nights
      @sold_nights ||= stays.select(&:confirmed?).sort_by { it.ical? ? 0 : 1 }.each_with_object({}) do |booking, by_room|
        nights = by_room[booking.room_id] ||= {}
        dates(booking).each { nights[it] ||= booking }
      end
    end

    def arrivals
      @arrivals ||= Booking.where(room_id: place.rooms.select(:id), start_date: range).includes(:calendar_feed).to_a
    end

    def priced = rooms.select { it.room.price }

    # The booking's nights inside the month.
    def dates(booking) = ([ booking.start_date, month ].max...[ booking.occupied_until, month.next_month ].min).to_a

    def channel(booking) = booking.manual? ? "manual" : booking.calendar_feed&.provider || "other"

    def ratio(part, whole) = whole.zero? ? nil : part.to_f / whole
end
