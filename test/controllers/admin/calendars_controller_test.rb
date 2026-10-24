require "test_helper"

class Admin::CalendarsControllerTest < ActionDispatch::IntegrationTest
  setup do
    log_in users(:owner)
    travel_to Time.zone.local(2026, 10, 1, 12)
  end

  test "menu calendar goes to the first homestay, or the picked one" do
    get admin_calendar_path
    assert_redirected_to admin_place_calendar_path("tomo-homestay")
    get admin_calendar_path(slug: "tomo-homestay")
    assert_redirected_to admin_place_calendar_path("tomo-homestay")
    get admin_calendar_path(slug: "hiuhill-homestay")
    assert_response :not_found
  end

  test "another owner's calendar is not found" do
    get admin_place_calendar_path("hiuhill-homestay")
    assert_response :not_found
  end

  test "Bảo trì days can't be booked; a booking already there is a conflict" do
    rooms(:limdim).update!(housekeeping: "maintenance", maintenance_reason: "Sơn lại", maintenance_until: "2026-10-02")
    get admin_place_calendar_path("tomo-homestay")
    assert_select "[data-room='#{rooms(:limdim).id}'] [data-maintenance-day]", 2 # 01/10, 02/10
    assert_select "a[aria-label='Đặt Limdim ngày 02/10']", 0
    assert_select "a[aria-label='Đặt Limdim ngày 03/10']"
    assert_select "#booking_#{bookings(:limdim_confirmed).id}[data-conflict]"
    assert_select "[role=alert]", text: /Limdim bảo trì đến 02\/10 nhưng có “Anh Minh”/
  end

  test "timeline shows active rooms, blocking bookings in range; iCal bars are read-only" do
    rooms(:garden).update!(active: false)
    ical = Booking.create!(room: rooms(:limdim), start_date: "2026-10-05", end_date: "2026-10-07", source: "ical",
      calendar_feed: calendar_feeds(:limdim_airbnb), uid: "a")
    cancelled = Booking.create!(room: rooms(:limdim), start_date: "2026-10-08", end_date: "2026-10-09", status: "cancelled", guest_name: "Huỷ")
    Booking.create!(room: rooms(:limdim), start_date: "2026-11-01", end_date: "2026-11-02", guest_name: "Tháng sau")

    get admin_place_calendar_path("tomo-homestay")
    assert_response :success
    assert_select "[data-room]", 1
    assert_select "a#booking_#{bookings(:limdim_confirmed).id}[href=?]", edit_admin_booking_path(bookings(:limdim_confirmed)), text: "! Anh Minh" # no deposit yet
    assert_select "div#booking_#{ical.id}[title=?]", "#{ical.code} · Airbnb", text: "Airbnb"
    assert_select "a#booking_#{ical.id}", 0
    assert_select "#booking_#{cancelled.id}", 0
    assert_select "body", text: /Tháng sau/, count: 0
    assert_select "[data-conflict]", 0
  end

  test "iCal booking overlapping a manual one is shown as a conflict" do
    ical = Booking.create!(room: rooms(:limdim), start_date: "2026-10-02", end_date: "2026-10-04", source: "ical",
      calendar_feed: calendar_feeds(:limdim_airbnb), uid: "a")

    get admin_place_calendar_path("tomo-homestay")
    assert_select "#booking_#{ical.id}[data-conflict]"
    assert_select "#booking_#{bookings(:limdim_confirmed).id}[data-conflict]"
    assert_select "[role=alert]", text: /Limdim.*Airbnb.*Anh Minh/m
  end

  test "checked-out bookings are muted with a tick, and the legend says so" do
    booking = bookings(:limdim_confirmed)
    booking.check_in
    booking.check_out
    get admin_place_calendar_path("tomo-homestay")
    assert_select "a#booking_#{booking.id}.bg-primary\\/15", text: "✓ Anh Minh"
    assert_select "span", text: "✓ Đã trả phòng"
  end

  test "an overdue guest's bar runs through today until check-out" do
    travel_to Time.zone.local(2026, 10, 4, 9)
    booking = bookings(:limdim_confirmed) # 1/10–3/10
    booking.update_columns(checked_in_at: Time.zone.local(2026, 10, 1, 14))
    get admin_place_calendar_path("tomo-homestay")
    assert_select "a#booking_#{booking.id}.bg-error\\/15[style*='grid-column: 2 / 3']", text: "Anh Minh · quá hạn"
    assert_select "span", text: "Quá hạn chưa trả phòng"

    booking.check_out
    get admin_place_calendar_path("tomo-homestay")
    assert_select "#booking_#{booking.id}", count: 0 # back to its booked dates, all before today
  end

  test "a guest due out today has no bar but is listed under the room" do
    travel_to Time.zone.local(2026, 10, 3, 9)
    booking = bookings(:limdim_confirmed) # 1/10–3/10
    booking.update_columns(checked_in_at: Time.zone.local(2026, 10, 1, 14))
    get admin_place_calendar_path("tomo-homestay")
    assert_select "#booking_#{booking.id}", count: 0
    assert_select "[data-room='#{rooms(:limdim).id}'] [data-departing]", text: "Trả: Anh Minh"
    assert_select "a[aria-label='Đặt Limdim ngày 03/10']"

    get admin_place_calendar_path("tomo-homestay", from: "2026-10-20")
    assert_select "[data-departing]", count: 0
  end

  test "from moves the range and bad dates fall back to today" do
    get admin_place_calendar_path("tomo-homestay", from: "2026-10-15")
    assert_select "[data-day='2026-10-15']"
    assert_select "[data-day='2026-10-01']", 0

    get admin_place_calendar_path("tomo-homestay", from: "nope")
    assert_select "[data-day='2026-10-01']"
  end

  test "empty cells link to a prefilled new booking" do
    get admin_place_calendar_path("tomo-homestay")
    assert_select "a[href=?]", new_admin_place_booking_path("tomo-homestay", room_id: rooms(:garden).id, start_date: "2026-10-05")
  end

  test "Loại phòng filter shows only rooms of that type; another homestay's type is not found" do
    double = places(:tomo).room_types.create!(name: "Phòng đôi")
    rooms(:garden).update!(room_type: double)
    log_in users(:owner)
    get admin_place_calendar_path("tomo-homestay", type: double.id)
    assert_select "select[name=type] option[selected]", text: "Phòng đôi"
    assert_select "[data-room]", 1
    assert_select "[data-room='#{rooms(:garden).id}']"
    assert_select "a[aria-label='Sau'][href*='type=#{double.id}']"

    get admin_place_calendar_path("tomo-homestay", type: places(:hiuhill).room_types.create!(name: "x").id)
    assert_response :not_found
  end
end
