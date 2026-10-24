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

  test "clips nights at month edges; cancellations don't sell" do
    book(@limdim, "2026-09-29", "2026-10-01")                     # September only
    book(@limdim, "2026-10-30", "2026-11-02")                     # 2 nights in October
    book(@garden, "2026-10-05", "2026-10-07")                     # 2 nights
    book(@garden, "2026-10-20", "2026-10-21", status: "cancelled")

    r = report(Date.new(2026, 10, 15))
    assert_equal Date.new(2026, 10, 1), r.month
    assert_equal 31, r.days
    assert_equal [ [ "Garden", 2 ], [ "Limdim", 4 ] ], r.rooms.map { [ it.room.name, it.sold ] }
    assert_equal [ 6, 62 ], [ r.sold, r.available ]
    assert_in_delta 6 / 62.0, r.occupancy
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
    assert_equal({ nights: 2 + 2, bookings: 2, revenue: 800_000, commission: nil, net: 800_000 }, r.channels["manual"])
    assert_equal({ nights: 3, bookings: 1, revenue: 1_200_000, commission: nil, net: 1_200_000 }, r.channels["airbnb"])
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
    book(@garden, "2026-10-05", "2026-10-07")
    book(@garden, "2026-10-20", "2026-10-21", status: "cancelled")
    airbnb("2026-10-10", "2026-10-14")
    PaperTrail.request(whodunnit: "airbnb") { airbnb("2026-10-25", "2026-10-26", uid: "gone").destroy! }
    PaperTrail.request(whodunnit: "airbnb") { airbnb("2026-11-25", "2026-11-26", uid: "nov").destroy! }

    r = report
    assert_equal 4, r.booking_count
    assert_equal({ "confirmed" => 3, "cancelled" => 1 }, r.outcomes)
    assert_in_delta (2 + 2 + 4) / 3.0, r.alos
    assert_equal 1, r.ota_cancelled
    assert_in_delta 2 / 5.0, r.cancellation_rate
  end

  test "a night shared by an iCal and a manual booking (calendar conflict) sells once, to the OTA" do
    airbnb("2026-10-02", "2026-10-04")                         # overlaps limdim_confirmed 10-01..10-03 on 10-02

    r = report
    assert_equal 3, r.sold
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
    book(@garden, "2026-10-25", "2026-10-26")                     # after today: ahead
    book(@limdim, "2026-09-05", "2026-09-07")                     # inside 1–20/9
    book(@limdim, "2026-09-25", "2026-09-27")                     # after 20/9

    r = Report.new(@place, Date.current)
    assert r.current? && r.partial?
    assert_equal [ Date.new(2026, 10, 20), 20, 40 ], [ r.last, r.days, r.available ]
    assert_equal [ 2 + 2, 2 ], [ r.sold, r.booking_count ] # fixture 10-01..03 + 19, 20
    assert_equal [ 3, 800_000 ], [ r.ahead, r.ahead_revenue ] # garden is unpriced
    assert_equal [ Date.new(2026, 9, 20), 2 ], [ r.previous.last, r.previous.sold ]

    september = Report.new(@place, Date.new(2026, 9, 1))
    assert_not september.partial?
    assert_equal [ Date.new(2026, 8, 31), 4 ], [ september.previous.last, september.sold ]
    november = Report.new(@place, Date.new(2026, 11, 1))
    assert november.future?
    assert_equal [ Date.new(2026, 11, 30), 0 ], [ november.last, november.ahead ]
  end

  test "Doanh thu adds services and takes off Giảm giá, spread over the booking's nights; ADR stays room only" do
    stay = book(@limdim, "2026-10-30", "2026-11-03", price: 400_000) # 2 nights in October, 2 in November
    stay.charges.create!(name: "Giặt ủi", unit_price: 30_000, quantity: 4)
    stay.update!(discount: 40_000, discount_reason: "Khách quen")
    # extra = (120k − 40k) / 4 = 20k a night
    assert_equal 800_000 + 2 * 400_000 + 2 * 20_000, report.revenue # + fixture 10-01..03
    assert_in_delta 400_000.0, report.adr
    assert_equal 2 * 420_000, report(Date.new(2026, 11, 1)).revenue
  end

  test "Thực nhận takes off the OTA's commission; Công nợ lists direct bookings with money due, overdue once left" do
    @place.update!(commissions: { "airbnb" => "15" })
    airbnb("2026-10-10", "2026-10-12")
    assert_equal({ nights: 2, bookings: 1, revenue: 800_000, commission: 15.0, net: 680_000 }, report.channels["airbnb"])

    left = bookings(:limdim_confirmed).tap { it.update!(price: 400_000) } # 10-01..03, nothing paid
    staying = book(@garden, "2026-10-19", "2026-10-22", price: 300_000)
    staying.payments.create!(amount: 300_000, payment_method: "cash")
    book(@limdim, "2026-10-25", "2026-10-26", price: 400_000) # after today: not owed yet
    r = Report.new(@place, Date.current)
    assert_equal [ left, staying ], r.debts
    assert_equal 800_000 + 600_000, r.due
    assert_equal [ true, false ], r.debts.map { r.overdue?(it) }
  end

  test "7 ngày: the week through today, compared with the week before" do
    book(@limdim, "2026-10-13", "2026-10-15") # 13 the week before, 14 this week
    book(@limdim, "2026-10-18", "2026-10-22") # 18, 19, 20; the period ends today, so nothing ahead
    r = Report.week(@place)
    assert_not r.month?
    assert_equal [ Date.new(2026, 10, 14), Date.new(2026, 10, 20), 7 ], [ r.first, r.last, r.days ]
    assert_equal [ 4, 0 ], [ r.sold, r.ahead ]
    assert_equal [ Date.new(2026, 10, 7), Date.new(2026, 10, 13), 1 ], [ r.previous.first, r.previous.last, r.previous.sold ]
  end

  test "top rooms by revenue, at most 5" do
    6.times { |i| @place.rooms.create!(name: "P#{i}", max_guests: 2, price: 100_000 * (i + 1)).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06") }
    assert_equal %w[Limdim P5 P4 P3 P2], report.top_rooms.map { it.room.name } # Limdim: fixture 2 × 400k
  end

  test "CSV: one line per booking, Excel friendly, formulas neutralised" do
    book(@limdim, "2026-10-30", "2026-11-02", price: 400_000, guest_name: "=HYPERLINK(\"x\")")
    csv = report.to_csv
    assert csv.start_with?("\uFEFF\"Mã\",\"Phòng\",\"Khách\",")
    lines = csv.split("\r\n")
    assert_equal 3, lines.size # header, fixture, the booking
    assert_match(/"Limdim","'=HYPERLINK\(""x""\)","30\/10\/2026","02\/11\/2026","Trực tiếp",2,800000,1200000\z/, lines.last)
  end
end
