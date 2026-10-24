# One homestay, one period (a calendar month, or the last 7 days) in numbers for owners (#77, #141).
# A night is a date slept (end_date exclusive). Nights sold follow Booking#occupied_until, like vacancy.
# Revenue (Doanh thu) is each night at its booking's quoted price (Booking#price_on) plus the booking's services minus its
# Giảm giá, spread evenly over its nights (#140); money not yet collected included. Unpriced nights are left out of ADR.
# A period in progress counts through today (`last`); confirmed nights after today are `ahead` (#117).
class Report
  CHANNEL_LABELS = { "manual" => "Trực tiếp" }.merge(CalendarFeed::PROVIDER_LABELS).freeze
  CSV_HEADER = [ "Mã", "Phòng", "Khách", "Nhận phòng", "Trả phòng", "Nguồn", "Đêm trong kỳ", "Doanh thu trong kỳ", "Còn phải thu" ].freeze

  # revenue: nil for a room without a price and no priced night. room_revenue: nights only. unpriced: nights sold without a price.
  RoomRow = Data.define(:room, :sold, :revenue, :room_revenue, :unpriced)

  attr_reader :place, :first, :finish, :last

  # The calendar month of `first`, or first..finish.
  def initialize(place, first, finish = nil, last: nil)
    @place = place
    @first, @finish = finish ? [ first, finish ] : [ first.beginning_of_month, first.end_of_month ]
    @last = last || ((@first..@finish).cover?(Date.current) ? Date.current : @finish)
  end

  # 7 ngày: the week through today.
  def self.week(place) = new(place, Date.current - 6, Date.current)

  def month? = first.day == 1 && finish == first.end_of_month
  def month = first
  def current? = (first..finish).cover?(Date.current)
  def future? = first > Date.current
  def partial? = last < finish
  def days = (last - first).to_i + 1

  # A month in progress compares with the same days of the month before; 7 ngày with the 7 days before.
  def previous
    return Report.new(place, first - 7, finish - 7) unless month?
    prev = first.prev_month
    Report.new(place, prev, last: ([ prev + days - 1, prev.end_of_month ].min if partial?))
  end

  # Active rooms, plus inactive ones that sold nights in the period.
  def rooms
    @rooms ||= place.rooms.order(:name).map { |room|
      sold = sold_nights.fetch(room.id, {}).select { |date, _| date <= last }
      prices = sold.map { |date, booking| booking.price_on(date) }
      room_revenue = prices.compact.sum
      revenue = (room_revenue + sold.sum { |_, booking| extra(booking) }).round
      RoomRow.new(room:, sold: sold.size, revenue: (revenue unless room.price.nil? && room_revenue.zero?), room_revenue:, unpriced: prices.count(nil))
    }.select { it.room.active? || it.sold.positive? }
  end

  def top_rooms = rooms.each_with_index.sort_by { |row, index| [ -(row.revenue || 0), index ] }.first(5).map(&:first)

  def sold = rooms.sum(&:sold)
  def available = rooms.size * days
  def occupancy = ratio(sold, available)

  def revenue = rooms.sum { it.revenue || 0 }
  def adr = ratio(rooms.sum(&:room_revenue), sold - rooms.sum(&:unpriced))
  def unpriced? = rooms.any? { it.unpriced.positive? }

  # Confirmed nights after today in the period, and their revenue.
  def ahead = ahead_nights.size
  def ahead_revenue = ahead_nights.sum { night_revenue(*it) }.round

  def empty? = sold.zero? && booking_count.zero? && ota_cancelled.zero?

  # { "manual" => { nights:, bookings:, revenue:, commission:, net: }, "airbnb" => ... }: channels with any night or booking.
  # net = Thực nhận: revenue minus the OTA's commission % set on Kênh OTA (#125); commission nil = none set.
  def channels
    @channels ||= begin
      sold_by = sold_nights.values.flat_map { it.select { |date, _| date <= last }.to_a }.group_by { |_, booking| channel(booking) }
      arrivals_by = arrivals.group_by { channel(it) }
      CHANNEL_LABELS.keys.filter_map do |key|
        next unless sold_by[key] || arrivals_by[key]
        nights = sold_by.fetch(key, []) # [date, booking] per night sold
        revenue = nights.sum { night_revenue(*it) }.round
        commission = place.commissions[key]
        [ key, { nights: nights.size, bookings: arrivals_by.fetch(key, []).size, revenue:, commission:, net: (revenue * (100 - commission.to_f) / 100).round } ]
      end.to_h
    end
  end

  # Công nợ chưa thu: direct bookings with a night in the period and money still due, earliest check-out first.
  def debts = @debts ||= stays.select { it.manual? && it.start_date <= last && it.due&.positive? }.sort_by { [ it.end_date, it.id ] }
  def due = debts.sum(&:due)
  # Quá hạn: the guest has left, or should have.
  def overdue?(booking) = booking.checked_out_at.present? || booking.end_date <= Date.current

  def booking_count = arrivals.size
  def outcomes = %w[confirmed cancelled].index_with { |status| arrivals.count { it.status == status } }
  def alos = ratio(arrivals.select(&:confirmed?).sum { (it.end_date - it.start_date).to_i }, outcomes["confirmed"])

  # iCal bookings the sync deleted (the OTA cancelled them), by their start_date in the activity log.
  def ota_cancelled
    @ota_cancelled ||= PaperTrail::Version.where(place_id: place.id, item_type: "Booking", event: "destroy")
      .where("json_extract(object, '$.source') = 'ical'")
      .where("json_extract(object, '$.start_date') BETWEEN ? AND ?", first.iso8601, last.iso8601).count
  end

  def cancellation_rate = ratio(outcomes["cancelled"] + ota_cancelled, booking_count + ota_cancelled)

  # Xuất CSV: one line per booking with a night in the period. UTF-8 with a BOM so Excel reads Vietnamese.
  def to_csv
    by_booking = sold_nights.values.flat_map { it.select { |date, _| date <= last }.to_a }.group_by(&:last)
    lines = by_booking.sort_by { |booking, _| [ booking.start_date, booking.id ] }.map do |booking, nights|
      [ booking.code, booking.room.name, booking.guest_name, booking.start_date.strftime("%d/%m/%Y"), booking.end_date.strftime("%d/%m/%Y"),
        CHANNEL_LABELS.fetch(channel(booking)), nights.size, nights.sum { night_revenue(*it) }.round, booking.due ]
    end
    "﻿" + [ CSV_HEADER, *lines ].map { |line| line.map { csv_cell(it) }.join(",") + "\r\n" }.join
  end

  private
    def range = first..last

    def stays
      @stays ||= Booking.where(room_id: place.rooms.select(:id)).occupying(first, finish + 1)
        .includes(:room, :calendar_feed, :charges, :payments).to_a
    end

    # { room_id => { date => the confirmed booking that sold that night } } for the whole period. A night shared by an iCal and a
    # manual booking (a calendar conflict) is sold once, to the OTA.
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

    # The booking's nights inside the period.
    def dates(booking) = ([ booking.start_date, first ].max...[ booking.occupied_until, finish + 1 ].min).to_a

    # One night's share of the booking's services minus its Giảm giá.
    def extra(booking)
      (@extras ||= {})[booking.id] ||= (booking.charges.sum(&:amount) - booking.discount.to_i).to_r / [ (booking.end_date - booking.start_date).to_i, 1 ].max
    end

    def night_revenue(date, booking) = (booking.price_on(date) || 0) + extra(booking)

    def channel(booking) = booking.manual? ? "manual" : booking.calendar_feed&.provider || "other"

    def ratio(part, whole) = whole.zero? ? nil : part.to_f / whole

    # Numbers as is; text quoted, and a leading = + - @ neutralised so Excel doesn't run it as a formula.
    def csv_cell(value)
      return value.to_s if value.nil? || value.is_a?(Integer)
      text = value.to_s
      text = "'#{text}" if text.start_with?("=", "+", "-", "@", "\t", "\r")
      "\"#{text.gsub('"', '""')}\""
    end
end
