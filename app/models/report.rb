# One homestay, one calendar month: occupancy, estimated revenue and booking activity for owners (#77).
# A night is a date slept (end_date exclusive). Nights sold follow Booking#occupied_until, like vacancy.
# Revenue is an estimate: each night at its booking's quoted price (Booking#price_on); unpriced nights are left out of revenue and ADR.
# The current month counts the 1st through today (`last`); confirmed nights after today are `ahead` (#117).
class Report
  CHANNEL_LABELS = { "manual" => "Trực tiếp" }.merge(CalendarFeed::PROVIDER_LABELS).freeze

  # revenue: nil for a room without a price and no priced night. unpriced: nights sold without a price.
  RoomRow = Data.define(:room, :sold, :held, :revenue, :unpriced)

  attr_reader :place, :month, :last

  def initialize(place, month, last: nil)
    @place = place
    @month = month.beginning_of_month
    @last = last || (current? ? Date.current : @month.end_of_month)
  end

  def current? = month == Date.current.beginning_of_month
  def future? = month > Date.current
  def partial? = last < month.end_of_month
  def days = (last - month).to_i + 1

  # A month in progress compares with the same days of the month before.
  def previous
    prev = month.prev_month
    Report.new(place, prev, last: ([ prev + days - 1, prev.end_of_month ].min if partial?))
  end

  # Active rooms, plus inactive ones that sold nights this month.
  def rooms
    @rooms ||= place.rooms.order(:name).map { |room|
      sold = sold_nights.fetch(room.id, {}).select { |date, _| date <= last }
      held = stays.select { it.hold? && it.room_id == room.id }.flat_map { dates(it) }.uniq.select { it <= last } - sold.keys
      prices = sold.map { |date, booking| booking.price_on(date) }
      revenue = prices.compact.sum
      RoomRow.new(room:, sold: sold.size, held: held.size, revenue: (revenue unless room.price.nil? && revenue.zero?), unpriced: prices.count(nil))
    }.select { it.room.active? || it.sold.positive? }
  end

  def sold = rooms.sum(&:sold)
  def held = rooms.sum(&:held)
  def available = rooms.size * days
  def occupancy = ratio(sold, available)

  def revenue = rooms.sum { it.revenue || 0 }
  def adr = ratio(revenue, sold - rooms.sum(&:unpriced))
  def unpriced? = rooms.any? { it.unpriced.positive? }

  # Confirmed nights after today in the current month, and their estimated revenue.
  def ahead = ahead_nights.size
  def ahead_revenue = ahead_nights.sum { |date, booking| booking.price_on(date) || 0 }

  def empty? = sold.zero? && held.zero? && booking_count.zero? && ota_cancelled.zero?

  # { "manual" => { nights:, bookings:, revenue: }, "airbnb" => ... }: channels with any night or booking.
  def channels
    @channels ||= begin
      sold_by = sold_nights.values.flat_map { it.select { |date, _| date <= last }.to_a }.group_by { |_, booking| channel(booking) }
      arrivals_by = arrivals.group_by { channel(it) }
      CHANNEL_LABELS.keys.filter_map do |key|
        next unless sold_by[key] || arrivals_by[key]
        nights = sold_by.fetch(key, []) # [date, booking] per night sold
        [ key, { nights: nights.size, bookings: arrivals_by.fetch(key, []).size, revenue: nights.sum { |date, booking| booking.price_on(date) || 0 } } ]
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
      .where("json_extract(object, '$.start_date') BETWEEN ? AND ?", month.iso8601, last.iso8601).count
  end

  def cancellation_rate = ratio(outcomes["cancelled"] + ota_cancelled, booking_count + ota_cancelled)

  private
    def range = month..last

    def stays
      @stays ||= Booking.where(room_id: place.rooms.select(:id)).occupying(month, month.next_month)
        .includes(:room, :calendar_feed).to_a
    end

    # { room_id => { date => the confirmed booking that sold that night } } for the whole month. A night shared by an iCal and a manual
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

    def ahead_nights = sold_nights.values.flat_map { it.select { |date, _| date > last }.to_a }

    # The booking's nights inside the month.
    def dates(booking) = ([ booking.start_date, month ].max...[ booking.occupied_until, month.next_month ].min).to_a

    def channel(booking) = booking.manual? ? "manual" : booking.calendar_feed&.provider || "other"

    def ratio(part, whole) = whole.zero? ? nil : part.to_f / whole
end
