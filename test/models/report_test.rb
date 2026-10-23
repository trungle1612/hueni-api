require "test_helper"

class ReportTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.local(2026, 10, 20, 12)
    @place = places(:tomo)
    @limdim = rooms(:limdim).tap { it.update!(price: 400_000) } # garden stays unpriced
    @garden = rooms(:garden)
    # limdim_confirmed fixture: limdim 10-01..10-03, manual, confirmed → 2 nights
  end

  def book(room, from, to, **attrs) = room.bookings.create!(start_date: from, end_date: to, **attrs)

  def airbnb(from, to, uid: "a")
    calendar_feeds(:limdim_airbnb).bookings.create!(room: @limdim, uid:, start_date: from, end_date: to, source: "ical")
  end

  # The whole month, also for October (in progress on 10-20); the partial month has its own test.
  def report(month = Date.new(2026, 10, 1)) = Report.new(@place, month, last: month.end_of_month)

  test "clips nights at month edges; holds and cancellations don't sell" do
    book(@limdim, "2026-09-29", "2026-10-01")                     # September only
    book(@limdim, "2026-10-30", "2026-11-02")                     # 2 nights in October
    book(@garden, "2026-10-05", "2026-10-07", status: "hold")     # 2 held
    book(@garden, "2026-10-20", "2026-10-21", status: "cancelled")

    r = report(Date.new(2026, 10, 15))
    assert_equal Date.new(2026, 10, 1), r.month
    assert_equal 31, r.days
    assert_equal [ [ "Garden", 0, 2 ], [ "Limdim", 4, 0 ] ], r.rooms.map { [ it.room.name, it.sold, it.held ] }
    assert_equal [ 4, 2, 62 ], [ r.sold, r.held, r.available ]
    assert_in_delta 4 / 62.0, r.occupancy
    assert_equal 2, r.previous.sold
  end

  test "early check-out frees the rest; overdue guest counts through today" do
    early = book(@garden, "2026-10-14", "2026-10-18")
    early.update_columns(checked_in_at: Time.zone.local(2026, 10, 14, 14), checked_out_at: Time.zone.local(2026, 10, 15, 10))
    overdue = book(@limdim, "2026-10-16", "2026-10-19")
    overdue.update_columns(checked_in_at: Time.zone.local(2026, 10, 16, 14)) # still in on 10-20

    rows = report.rooms.to_h { [ it.room.name, it.sold ] }
    assert_equal 1, rows["Garden"]
    assert_equal 2 + 5, rows["Limdim"] # fixture + 16..20
  end

  test "revenue and ADR use priced rooms only" do
    book(@garden, "2026-10-05", "2026-10-07")
    airbnb("2026-10-10", "2026-10-13")

    r = report
    assert_equal [ 2_000_000, nil ], r.rooms.map(&:revenue).values_at(1, 0) # Limdim (2 + 3) × 400k, Garden unpriced
    assert_equal 2_000_000, r.revenue          # (2 + 3) × 400k
    assert_in_delta 400_000.0, r.adr
    assert r.unpriced?
    assert_equal({ nights: 2 + 2, bookings: 2, revenue: 800_000 }, r.channels["manual"])
    assert_equal({ nights: 3, bookings: 1, revenue: 1_200_000 }, r.channels["airbnb"])
    assert_equal %w[manual airbnb], r.channels.keys
  end

  test "revenue uses each booking's quoted price and weekend price, not the room's current price" do
    book(@garden, "2026-10-23", "2026-10-25", price: 300_000, weekend_price: 350_000) # Fri + Sat nights
    @limdim.update!(price: 999_000) # limdim_confirmed fixture has no quote → current price

    rows = report.rooms.to_h { [ it.room.name, it.revenue ] }
    assert_equal 700_000, rows["Garden"]
    assert_equal 2 * 999_000, rows["Limdim"]
    assert_not report.unpriced?
  end

  test "booking activity, ALOS, OTA cancellations and cancellation rate" do
    book(@garden, "2026-10-05", "2026-10-07", status: "hold")
    book(@garden, "2026-10-20", "2026-10-21", status: "cancelled")
    airbnb("2026-10-10", "2026-10-14")
    PaperTrail.request(whodunnit: "airbnb") { airbnb("2026-10-25", "2026-10-26", uid: "gone").destroy! }
    PaperTrail.request(whodunnit: "airbnb") { airbnb("2026-11-25", "2026-11-26", uid: "nov").destroy! }

    r = report
    assert_equal 4, r.booking_count
    assert_equal({ "confirmed" => 2, "hold" => 1, "cancelled" => 1 }, r.outcomes)
    assert_in_delta (2 + 4) / 2.0, r.alos
    assert_equal 1, r.ota_cancelled
    assert_in_delta 2 / 5.0, r.cancellation_rate
  end

  test "a night shared by an iCal and a manual booking (calendar conflict) sells once, to the OTA" do
    airbnb("2026-10-02", "2026-10-04")                         # overlaps limdim_confirmed 10-01..10-03 on 10-02
    @limdim.bookings.new(start_date: "2026-10-02", end_date: "2026-10-03", status: "hold").save!(validate: false) # held night already sold

    r = report
    assert_equal [ 3, 0 ], [ r.sold, r.held ]
    assert_equal 1_200_000, r.revenue
    assert_equal 1, r.channels["manual"][:nights]
    assert_equal 2, r.channels["airbnb"][:nights]
  end

  test "inactive rooms are listed only when they sold nights" do
    @garden.update!(active: false)
    @place.rooms.create!(name: "Gác", max_guests: 2, active: false)
    assert_equal [ "Limdim" ], report.rooms.map { it.room.name }

    book(@garden, "2026-10-05", "2026-10-06")
    assert_equal [ "Garden", "Limdim" ], report.rooms.map { it.room.name }
  end

  test "empty month has nil ratios" do
    r = Report.new(places(:hiuhill), Date.new(2026, 10, 1))
    assert_equal [ 0, 0, 0 ], [ r.sold, r.available, r.booking_count ]
    assert_nil r.occupancy
    assert_nil r.adr
    assert_nil r.alos
    assert_nil r.cancellation_rate
    assert r.empty?
    assert_not report.empty?
  end

  test "the current month counts through today; confirmed nights after today are booked ahead" do
    book(@limdim, "2026-10-19", "2026-10-23")                     # 19, 20 so far; 21, 22 ahead
    book(@garden, "2026-10-25", "2026-10-26", status: "hold")     # after today: not held yet
    book(@limdim, "2026-09-05", "2026-09-07")                     # inside 1–20/9
    book(@limdim, "2026-09-25", "2026-09-27")                     # after 20/9

    r = Report.new(@place, Date.current)
    assert r.current? && r.partial?
    assert_equal [ Date.new(2026, 10, 20), 20, 40 ], [ r.last, r.days, r.available ]
    assert_equal [ 2 + 2, 0, 2 ], [ r.sold, r.held, r.booking_count ] # fixture 10-01..03 + 19, 20
    assert_equal [ 2, 800_000 ], [ r.ahead, r.ahead_revenue ]
    assert_equal [ Date.new(2026, 9, 20), 2 ], [ r.previous.last, r.previous.sold ]

    september = Report.new(@place, Date.new(2026, 9, 1))
    assert_not september.partial?
    assert_equal [ Date.new(2026, 8, 31), 4 ], [ september.previous.last, september.sold ]
    november = Report.new(@place, Date.new(2026, 11, 1))
    assert november.future?
    assert_equal [ Date.new(2026, 11, 30), 0 ], [ november.last, november.ahead ]
  end
end
