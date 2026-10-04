require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  def log_in(user)
    post session_path, params: { phone_number: user.phone_number, password: "password123" }
  end

  test "requires login" do
    get admin_root_path
    assert_redirected_to new_session_path
  end

  test "root redirects to admin" do
    get root_path
    assert_redirected_to "/admin"
  end

  test "shows the dashboard to a logged-in user" do
    log_in users(:owner)
    get admin_root_path
    assert_response :success
    assert_select "h1", "Tổng quan"
  end

  test "public endpoints stay public" do
    get "/v1/vacancy"
    assert_response :success
    get "/up"
    assert_response :success
  end

  test "owner sees menu without users item" do
    log_in users(:owner)
    get admin_root_path

    assert_select "aside a[href='/admin']", text: /Tổng quan/
    assert_select "aside a[href='/admin/calendar']", text: /Lịch phòng/
    assert_select "aside a[href='/admin/calendar_feeds']", text: /Kênh OTA/
    assert_select "aside", text: /Người dùng/, count: 0
    assert_select ".dock a[href='/admin']"
  end

  test "admin also sees the users item" do
    log_in users(:admin)
    get admin_root_path
    assert_select "aside", text: /Người dùng/
    assert_select "aside a[href='/admin/users']", text: /Người dùng/
  end

  test "shows name, role and avatar initial, including Vietnamese letters" do
    users(:owner).update!(name: "ánh")
    log_in users(:owner)
    get admin_root_path

    assert_select ".avatar", text: "Á"
    assert_select "aside", text: /ánh/
    assert_select "aside", text: /Thành viên/, count: 0
    assert_select "aside button", text: "Đăng xuất"
  end

  test "owner sees only their homestays" do
    log_in users(:owner)
    get admin_root_path
    assert_select "main .card", text: /tomo homestay/
    assert_select "main", text: /6\/24 Kim Long/, count: 0 # no address on the dashboard
    assert_select "main", text: /Hiu Hill Homestay/, count: 0
  end

  test "admin sees every homestay" do
    log_in users(:admin)
    get admin_root_path
    assert_select "main .card", text: /tomo homestay/
    assert_select "main .card", text: /Hiu Hill Homestay/
  end

  test "cards link to the homestay page and show today's free rooms" do
    travel_to Time.zone.local(2026, 10, 1, 12) # limdim booked, garden free
    log_in users(:owner)
    get admin_root_path
    assert_select "main a[href='#{admin_place_path("tomo-homestay")}']", text: "tomo homestay"
    assert_select "main .badge", text: "Còn 1/2 phòng hôm nay"
  end

  test "fully booked homestay shows Hết phòng hôm nay" do
    travel_to Time.zone.local(2026, 10, 1, 12)
    Booking.create!(room: rooms(:garden), start_date: "2026-10-01", end_date: "2026-10-02", status: "hold")
    log_in users(:owner)
    get admin_root_path
    assert_select "main .badge", text: "Hết phòng hôm nay"
  end

  test "homestay with all rooms switched off shows Chưa có phòng" do
    Room.update_all(active: false)
    log_in users(:owner)
    get admin_root_path
    assert_select "main .badge", text: "Chưa có phòng"
  end

  test "counts only the user's failing feeds" do
    calendar_feeds(:limdim_airbnb).update_columns(last_error: "RuntimeError: HTTP 500", last_error_at: Time.current)
    other_room = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
    CalendarFeed.create!(room: other_room, url: "https://1.1.1.1/x.ics", provider: "other").update_columns(last_error: "boom", last_error_at: Time.current)

    log_in users(:owner)
    get admin_root_path
    assert_select "main a.badge[href='#{admin_calendar_feeds_path}']", text: "Lỗi đồng bộ (1)"

    users(:owner).place_memberships.delete_all # setup only: skips the last-owner rule
    users(:owner).places << places(:hiuhill)
    get admin_root_path
    assert_select "main .badge", text: "Lỗi đồng bộ (1)", count: 1
  end

  test "owner without homestays sees the empty state" do
    users(:owner).place_memberships.delete_all # setup only: skips the last-owner rule
    log_in users(:owner)
    get admin_root_path
    assert_select "main", text: /Chưa có homestay nào/
  end

  test "dashboard cards show the role only with several homestays; admins see none" do
    log_in users(:owner)
    get admin_root_path
    assert_select ".card .badge", text: "Chủ", count: 0

    places(:hiuhill).place_memberships.create!(user: users(:owner), role: "staff")
    get admin_root_path
    assert_select ".card", text: /tomo homestay.*Chủ/m
    assert_select ".card", text: /Hiu Hill Homestay.*Nhân viên/m

    delete session_path
    log_in users(:admin)
    get admin_root_path
    assert_select ".badge", text: "Chủ", count: 0
  end

  test "Hôm nay groups follow the day: departures, cleaning, arrivals, in-house, holds" do
    travel_to Time.zone.local(2026, 10, 2, 9)
    # limdim_confirmed (1/10–3/10, Anh Minh) is not checked in: a late arrival.
    bookings(:limdim_confirmed).update!(guest_phone: "0905 123 456")
    leaving = rooms(:garden).bookings.create!(start_date: "2026-09-30", end_date: "2026-10-02", guest_name: "Chị Mai")
    leaving.update_columns(checked_in_at: 2.days.ago)
    overdue = rooms(:garden).bookings.create!(start_date: "2026-09-28", end_date: "2026-09-30", guest_name: "Anh Tú")
    staying = rooms(:garden).bookings.create!(start_date: "2026-10-02", end_date: "2026-10-04", guest_name: "Cô Ba", guests: 2)
    overdue.update_columns(checked_in_at: 4.days.ago) # setup only: an overdue guest now blocks the room
    staying.update_columns(checked_in_at: 1.hour.ago)
    rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06", status: "hold", guest_name: "Chị Hoa")
    rooms(:garden).bookings.create!(start_date: "2026-10-10", end_date: "2026-10-12", status: "hold", guest_name: "Đoàn sau")
    rooms(:limdim).dirty!

    log_in users(:owner)
    get admin_root_path

    assert_equal %w[departures dirty_rooms arrivals in_house holds], css_select("#today .card-body > [id]").map { it["id"] }
    assert_select "#departures", text: /Anh Tú.*Quá hạn 2 ngày/m
    assert_select "#today_booking_#{leaving.id} .badge", count: 0
    assert_select "#departures form[action='#{check_out_admin_booking_path(leaving)}'][data-turbo-confirm='Chị Mai trả phòng Garden?']"
    assert_select "#dirty_rooms form[action='#{clean_admin_room_path(rooms(:limdim))}']"
    assert_select "#arrivals", text: /Anh Minh.*Trễ 1 ngày.*Phòng chưa dọn/m
    assert_select "#arrivals a[href='tel:0905123456']"
    assert_select "#arrivals form[action='#{check_in_admin_booking_path(bookings(:limdim_confirmed))}']"
    assert_select "#arrivals form[action='#{no_show_admin_booking_path(bookings(:limdim_confirmed))}']"
    assert_select "#today_booking_#{bookings(:limdim_confirmed).id}", text: /Phòng Limdim · 01\/10–03\/10/
    assert_select "#in_house", text: /Cô Ba · 2 khách/
    assert_select "#in_house form", count: 0
    assert_select "#holds summary", text: /Đang giữ chỗ\s*1/
    assert_select "#holds", text: /Chị Hoa/
    assert_select "#holds", text: /Đoàn sau/, count: 0 # starts in more than 3 days
    assert_select "#holds a[href='#{admin_calendar_path}']", text: "Xem lịch"
    assert_select "#stat_arrivals", text: /1\s*Sắp đến/
    assert_select "#stat_in_house", text: /1\s*Đang ở/
    assert_select "#stat_departures", text: /2\s*Trả phòng/
    assert_select "#stat_dirty_rooms", text: /1\s*Cần dọn/
  end

  test "homestay name shows in rows only for users with several homestays" do
    travel_to Time.zone.local(2026, 10, 1, 9)
    log_in users(:owner)
    get admin_root_path
    assert_select "#today_booking_#{bookings(:limdim_confirmed).id}", text: /tomo homestay/, count: 0

    delete session_path
    places(:tomo).place_memberships.create!(user: users(:admin), role: "owner")
    log_in users(:admin)
    get admin_root_path
    assert_select "#today_booking_#{bookings(:limdim_confirmed).id}", text: /Phòng Limdim · tomo homestay/
  end

  test "manual rows link to the booking, iCal rows to the calendar" do
    travel_to Time.zone.local(2026, 10, 1, 9)
    ical = calendar_feeds(:limdim_airbnb).bookings.create!(room: rooms(:garden), uid: "x@airbnb", start_date: "2026-10-01", end_date: "2026-10-02", source: "ical")
    log_in users(:owner)
    get admin_root_path
    assert_select "#today_booking_#{bookings(:limdim_confirmed).id} a[href='#{edit_admin_booking_path(bookings(:limdim_confirmed))}']"
    assert_select "#today_booking_#{ical.id} a[href='#{admin_place_calendar_path("tomo-homestay")}']", text: /Airbnb/
    assert_select "#today_booking_#{ical.id} form[action='#{no_show_admin_booking_path(ical)}']", count: 0
  end

  test "Hôm nay is hidden when there is nothing to do" do
    travel_to Time.zone.local(2027, 1, 1, 9)
    log_in users(:owner)
    get admin_root_path
    assert_select "#today", count: 0
  end

  test "Hôm nay and the board show only the user's homestays" do
    travel_to Time.zone.local(2026, 10, 1, 9)
    other_room = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2, housekeeping: "dirty")
    other_room.bookings.create!(start_date: "2026-10-01", end_date: "2026-10-02", guest_name: "Khách lạ")
    log_in users(:owner)
    get admin_root_path
    assert_select "#today"
    assert_select "main", text: /Khách lạ/, count: 0
    assert_select "#tile_room_#{other_room.id}", count: 0
  end

  test "room board shows each room's state, guest and dirty badge, linking to the room" do
    travel_to Time.zone.local(2026, 10, 2, 9)
    rooms(:limdim).dirty!
    rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06", guest_name: "Chị Hoa")
    log_in users(:owner)
    get admin_root_path

    limdim = "#tile_room_#{rooms(:limdim).id}"
    assert_select limdim, text: /Limdim.*Chờ khách.*Anh Minh.*trả 03\/10/m
    assert_select "#{limdim} .badge", text: "Chưa dọn"
    assert_select "#{limdim}[href='#{admin_place_path("tomo-homestay", anchor: "room_#{rooms(:limdim).id}")}']"
    assert_select "#tile_room_#{rooms(:garden).id}", text: /Garden.*Trống.*Khách tới: 05\/10/m
  end

  test "admins get Hôm nay and room boards only for homestays they are members of" do
    travel_to Time.zone.local(2026, 10, 1, 9)
    other_room = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2, housekeeping: "dirty")
    other_room.bookings.create!(start_date: "2026-10-01", end_date: "2026-10-02", guest_name: "Khách lạ")
    places(:tomo).place_memberships.create!(user: users(:admin), role: "staff")
    log_in users(:admin)
    get admin_root_path

    assert_select "#today_booking_#{bookings(:limdim_confirmed).id}"
    assert_select "#tile_room_#{rooms(:limdim).id}"
    assert_select "main", text: /Khách lạ/, count: 0
    assert_select "#tile_room_#{other_room.id}", count: 0
    assert_select "#dirty_rooms", count: 0
    assert_select "main .card", text: /tomo homestay/
    assert_select "main .card", text: /Hiu Hill Homestay/
  end

  test "admin without memberships sees the homestay list but no Hôm nay or room boards" do
    travel_to Time.zone.local(2026, 10, 1, 9)
    log_in users(:admin)
    get admin_root_path

    assert_select "#today", count: 0
    assert_select "[id^='tile_room_']", count: 0
    assert_select "main .card", text: /tomo homestay/
    assert_select "main .card", text: /Hiu Hill Homestay/
  end

  test "an arrival into a room whose guest hasn't left shows Phòng còn khách instead of Check-in" do
    travel_to Time.zone.local(2026, 10, 2, 9)
    leaving = rooms(:garden).bookings.create!(start_date: "2026-10-01", end_date: "2026-10-02", guest_name: "Chị Mai")
    arriving = rooms(:garden).bookings.create!(start_date: "2026-10-02", end_date: "2026-10-03", guest_name: "Cô Ba")
    leaving.update_columns(checked_in_at: 1.day.ago)
    log_in users(:owner)
    get admin_root_path
    assert_select "#today_booking_#{arriving.id}", text: /Phòng còn khách/
    assert_select "#today_booking_#{arriving.id} form[action$='/check_in']", count: 0
  end

  test "an in-house OTA stay removed from the feed is flagged" do
    travel_to Time.zone.local(2026, 10, 2, 9)
    stay = calendar_feeds(:limdim_airbnb).bookings.create!(room: rooms(:garden), uid: "x@airbnb", start_date: "2026-10-01", end_date: "2026-10-04", source: "ical")
    stay.update_columns(checked_in_at: 1.day.ago, removed_from_feed_at: 1.hour.ago)
    log_in users(:owner)
    get admin_root_path
    assert_select "#today_booking_#{stay.id} .badge", text: "OTA đã huỷ"
  end

  test "a late arrival stays in Hôm nay until 06:00" do
    travel_to Time.zone.local(2026, 10, 3, 0, 30) # Anh Minh: 1/10–3/10
    log_in users(:owner)
    get admin_root_path
    assert_select "#arrivals #today_booking_#{bookings(:limdim_confirmed).id} form[action$='/check_in']"
    assert_select "#today_booking_#{bookings(:limdim_confirmed).id}", text: /Trễ 1 ngày/

    travel_to Time.zone.local(2026, 10, 3, 6)
    get admin_root_path
    assert_select "#today_booking_#{bookings(:limdim_confirmed).id}", count: 0
  end
end
