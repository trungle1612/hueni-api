require "test_helper"

# Fixtures: tomo has limdim (confirmed 1/10–3/10, Anh Minh, not checked in) and garden (no bookings).
class TodayTest < ActiveSupport::TestCase
  setup { travel_to Time.zone.local(2026, 10, 2, 9) }

  def today(**) = Today.new(places(:tomo).rooms, **)
  def anh_minh = bookings(:limdim_confirmed)

  test "arrivals include a guest due yesterday until LATE_ARRIVAL_UNTIL" do
    assert_equal [ anh_minh ], today.arrivals
    travel_to(Time.utc(2026, 10, 2, 17, 30)) { assert_equal [ anh_minh ], today.arrivals } # 00:30 on 3/10
    travel_to(Time.zone.local(2026, 10, 3, Booking::LATE_ARRIVAL_UNTIL)) { assert_empty today.arrivals }
  end

  test "in-house guests, then departures on and after end_date" do
    anh_minh.update_columns(checked_in_at: 1.day.ago)
    assert_equal [ [], [ anh_minh ] ], [ today.departures, today.in_house ]
    travel_to(Time.zone.local(2026, 10, 3, 9)) { assert_equal [ [ anh_minh ], [] ], [ today.departures, today.in_house ] }
  end

  test "dirty rooms, only from the rooms given" do
    rooms(:garden).dirty!
    assert_equal [ rooms(:garden) ], today.dirty_rooms
    assert_empty Today.new(Room.where(id: rooms(:limdim))).dirty_rooms
  end

  test "only bookings in the rooms given" do
    assert_empty Today.new(Room.where(id: rooms(:garden))).arrivals
  end

  test "Cần xử lý: OTA conflict, arrival to a dirty room, guest in without lưu trú" do
    calendar_feeds(:limdim_airbnb).bookings.create!(room: rooms(:limdim), uid: "a", start_date: "2026-10-02", end_date: "2026-10-04", source: "ical")
    cô_ba = rooms(:garden).bookings.create!(start_date: "2026-10-01", end_date: "2026-10-05", guest_name: "Cô Ba")
    cô_ba.update_columns(checked_in_at: 1.day.ago)
    rooms(:limdim).dirty!

    issues = today.issues
    conflict = issues.find { it.kind == :error }
    assert_equal [ "Trùng lịch OTA", "Airbnb và Anh Minh · Phòng Limdim · 02/10", anh_minh, Date.new(2026, 10, 2) ],
      [ conflict.title, conflict.detail, conflict.booking, conflict.date ]
    assert_equal [ "Anh Minh", "Airbnb" ].sort, issues.select { it.kind == :clean }.map { it.booking.label }.sort
    assert_equal [ [ "Chưa khai báo lưu trú", cô_ba ] ], issues.select { it.kind == :stay }.map { [ it.title, it.booking ] }

    cô_ba.declare
    assert_empty today.issues.select { it.kind == :stay }
  end

  test "Ngày mai: arrivals, departures, Sẽ cần dọn, who stays on; Cần xử lý stays today's" do
    cô_ba = rooms(:garden).bookings.create!(start_date: "2026-10-01", end_date: "2026-10-05", guest_name: "Cô Ba")
    cô_ba.update_columns(checked_in_at: 1.day.ago)
    chị_hoa = rooms(:garden).bookings.build(start_date: "2026-10-03", end_date: "2026-10-04", guest_name: "Chị Hoa")
    chị_hoa.save!(validate: false)

    tomorrow = today(tomorrow: true)
    assert_equal [ chị_hoa ], tomorrow.arrivals
    assert_equal [ anh_minh ], tomorrow.departures
    assert_equal [ rooms(:limdim) ], tomorrow.dirty_rooms
    assert_equal [ cô_ba ], tomorrow.in_house
    assert_equal today.issues, tomorrow.issues
  end
end
