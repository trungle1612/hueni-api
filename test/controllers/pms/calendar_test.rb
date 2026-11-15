require "test_helper"

# Lịch phòng in the PWA (#230): a week of the current homestay from RoomCalendar, like the /admin calendar.
class Pms::CalendarTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.local(2026, 10, 2, 9) }

  test "a week from today: bars open a sheet, free cells open Đặt phòng prefilled" do
    booking = bookings(:limdim_confirmed) # 1/10–3/10, no deposit
    log_in users(:owner)

    get pms_calendar_path
    assert_response :success
    assert_select "header", text: /Lịch phòng\s*02\/10 – 08\/10\/2026 · 2 phòng/
    assert_select "header a", text: "Hôm nay", count: 0
    assert_select "header a[aria-label='Tuần sau'][href=?]", pms_calendar_path(from: "2026-10-09")
    assert_select "nav a[aria-current=page]", text: "Lịch"
    assert_select "[data-day]", 7
    # Began before today: full start, ends mid-cell on the checkout morning of 3/10.
    assert_select "button#booking_#{booking.id}.pms-bar-warn[popovertarget=peek_booking_#{booking.id}][style*='grid-column: 2 / span 2']", text: "! Anh Minh"
    assert_select "#peek_booking_#{booking.id}[popover]", text: /Chưa cọc.*Anh Minh.*Phòng Limdim · 01 – 03\/10 · 2 đêm/m
    assert_select "#peek_booking_#{booking.id} a[href=?]", pms_booking_path(booking), text: "Mở đặt phòng"
    # The night of 2/10 is taken; 3/10 is free again.
    assert_select "a[aria-label^='Phòng Limdim, 02/10']", 0
    assert_select "a[aria-label='Phòng Limdim, 03/10, trống. Đặt phòng'][href=?]",
      new_pms_booking_path(room_id: rooms(:limdim).id, start_date: "2026-10-03")
  end

  test "iCal conflicts are shown, not rejected; OTA đã huỷ is a badge" do
    ical = Booking.create!(room: rooms(:limdim), start_date: "2026-10-02", end_date: "2026-10-04", source: "ical",
      calendar_feed: calendar_feeds(:limdim_airbnb), uid: "a", removed_from_feed_at: Time.current)
    log_in users(:owner)

    get pms_calendar_path
    assert_select "#conflicts a.pms-notice[href=?]", pms_booking_path(bookings(:limdim_confirmed)), text: /Trùng lịch · Limdim: Airbnb 02 – 04\/10 trùng với “Anh Minh”/
    assert_select "button#booking_#{ical.id}.pms-bar-conflict", text: "⚠ Airbnb"
    assert_select "button#booking_#{bookings(:limdim_confirmed).id}.pms-bar-conflict"
    assert_select "#peek_booking_#{ical.id} .pms-badge", text: "OTA đã huỷ"
    assert_select "#peek_booking_#{ical.id} .pms-badge", text: "Trùng lịch"
    assert_select "#peek_booking_#{ical.id} a[href=?]", pms_booking_path(ical), text: "Mở đặt phòng"
    # Two bars on one room: two 52px lanes.
    assert_select "#calendar_room_#{rooms(:limdim).id}[style*='repeat(2, 52px)']"
  end

  test "Bảo trì: a bar from today, no free cells, a booking there is a conflict" do
    rooms(:limdim).update!(housekeeping: "maintenance", maintenance_reason: "Sơn lại", maintenance_until: "2026-10-04")
    log_in users(:owner)

    get pms_calendar_path
    assert_select "button.pms-bar-maint[style*='grid-column: 2 / span 4']", "Bảo trì"
    assert_select "#maintenance_room_#{rooms(:limdim).id}", text: /Bảo trì phòng Limdim.*Sơn lại · đến 04\/10/m
    assert_select "a[aria-label^='Phòng Limdim, 04/10']", 0
    assert_select "a[aria-label^='Phòng Limdim, 05/10']"
    assert_select "#conflicts", text: /Limdim bảo trì đến 04\/10 nhưng có “Anh Minh”/
  end

  test "another week: Hôm nay comes back, past days can't be booked, empty week says so" do
    log_in users(:owner)
    get pms_calendar_path(from: "2026-09-26")
    assert_select "header a[href=?]", pms_calendar_path, text: "Hôm nay"
    assert_select "header a[aria-label='Tuần trước'][href=?]", pms_calendar_path(from: "2026-09-19")
    assert_select "a[aria-label^='Phòng Garden, 01/10']", 0
    assert_select "a[aria-label^='Phòng Garden, 02/10']"

    get pms_calendar_path(from: "2026-11-01")
    assert_select "p", "Chưa có đặt phòng nào trong tuần này."
  end

  test "staff see the calendar of their homestay; nobody sees another homestay's bookings" do
    places(:tomo).place_memberships.create!(user: users(:admin), role: "staff")
    log_in users(:admin)
    get pms_calendar_path
    assert_response :success
    assert_select "#booking_#{bookings(:limdim_confirmed).id}"

    other = User.create!(name: "Chủ Hiu Hill", role: "user", phone_number: "0911111111", password: "secret-password-1")
    places(:hiuhill).place_memberships.create!(user: other, role: "owner")
    log_in other
    get pms_calendar_path
    assert_select "#booking_#{bookings(:limdim_confirmed).id}", 0
    patch pms_place_path("tomo-homestay")
    assert_response :not_found
  end
end
