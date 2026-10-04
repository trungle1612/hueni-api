require "test_helper"

# Fixtures: owner ↔ tomo (limdim 4 guests, garden 2 guests); limdim confirmed 2026-10-01..03.
class Admin::PlacesControllerTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.local(2026, 10, 1, 12) }

  def log_in(user)
    post session_path, params: { phone_number: user.phone_number, password: "password123" }
  end

  test "owner sees their homestay with rooms, prices and today's status" do
    rooms(:limdim).update!(price: 450_000)
    log_in users(:owner)
    get admin_place_path("tomo-homestay")

    assert_response :success
    assert_select "h1", "tomo homestay"
    assert_select "#room_#{rooms(:limdim).id}", text: /4 khách · 450\.000 ₫\/đêm/
    assert_select "#room_#{rooms(:limdim).id} .bg-primary\\/15 [data-state]", "Chờ khách"
    assert_select "#room_#{rooms(:garden).id}", text: /chưa có giá/
    assert_select "#room_#{rooms(:garden).id} [data-state]", "Trống"
    assert_select "a[href='#{new_admin_place_room_path("tomo-homestay")}']", text: /Thêm phòng/
    assert_select "main .badge", text: "Còn 1/2 phòng hôm nay"
    assert_select "#room_#{rooms(:limdim).id} a[href='#{edit_admin_room_path(rooms(:limdim))}'][aria-label='Sửa phòng Limdim']"
  end

  test "hold shows Giữ chỗ, confirmed wins over hold, switched-off shows Đã tắt" do
    Booking.create!(room: rooms(:garden), start_date: "2026-10-01", end_date: "2026-10-02", status: "hold")
    # Overlaps limdim_confirmed: manual overlaps are rejected, so this only happens alongside an iCal booking.
    Booking.new(room: rooms(:limdim), start_date: "2026-10-01", end_date: "2026-10-02", status: "hold").save!(validate: false)
    log_in users(:owner)
    get admin_place_path("tomo-homestay")
    assert_select "#room_#{rooms(:garden).id} [data-state]", "Giữ chỗ"
    assert_select "#room_#{rooms(:limdim).id} [data-state]", "Chờ khách"

    rooms(:limdim).update!(active: false)
    get admin_place_path("tomo-homestay")
    assert_select "#room_#{rooms(:limdim).id} [data-state]", "Đã tắt"
    assert_equal [ "room_#{rooms(:garden).id}", "room_#{rooms(:limdim).id}" ], css_select(".card[id^=room_]").map { it["id"] } # switched-off last
  end

  test "sync errors link to Kênh OTA" do
    calendar_feeds(:limdim_airbnb).update_columns(last_error: "RuntimeError: HTTP 404", last_error_at: Time.current)
    log_in users(:owner)
    get admin_place_path("tomo-homestay")
    assert_select "main a.badge[href='#{admin_calendar_feeds_path}']", text: "Lỗi đồng bộ (1)"
  end

  test "another owner's homestay is not found" do
    log_in users(:owner)
    get admin_place_path("hiuhill-homestay")
    assert_response :not_found
    assert_select "h1", "Không tìm thấy"
    assert_select "aside a", text: /Tổng quan/ # inside the admin layout, not the bare Rails page
    assert_select "body", text: /SELECT|place_memberships/, count: 0
  end

  test "admin can open any homestay" do
    log_in users(:admin)
    get admin_place_path("hiuhill-homestay")
    assert_response :success
    assert_select "main", text: /Chưa có phòng nào/
  end

  test "requires login" do
    get admin_place_path("tomo-homestay")
    assert_redirected_to new_session_path
  end

  test "each room has an on/off switch that submits to the room" do
    log_in users(:owner)
    get admin_place_path("tomo-homestay")
    assert_select "#room_#{rooms(:garden).id} form[action='#{admin_room_path(rooms(:garden))}'][data-controller=autosubmit] input[type=checkbox][name='room[active]'][data-action='change->autosubmit#submit']"
  end

  test "staff see rooms without prices or owner controls, and a Nhân viên badge" do
    rooms(:garden).update!(price: 300_000)
    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")
    log_in staff
    get admin_place_path("tomo-homestay")

    assert_response :success
    assert_select ".badge", text: "Nhân viên"
    assert_select "body", text: /300\.000/, count: 0
    assert_select "a", text: /Thêm phòng/, count: 0
    assert_select "[id^=room_] a[aria-label^='Sửa']", count: 0
    assert_select "input[type=checkbox][name='room[active]']", 0
    assert_select "#room_#{rooms(:garden).id}", text: /Đang mở/
  end

  test "owners see a Chủ badge and the owner controls" do
    log_in users(:owner)
    get admin_place_path("tomo-homestay")
    assert_select ".badge", text: "Chủ"
    assert_select "a", text: /Thêm phòng/
  end

  test "room cards show the guest, the next booking and the right action" do
    bookings(:limdim_confirmed).update!(guests: 3)
    rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-07", guest_name: "Chị Hoa")
    log_in users(:owner)
    get admin_place_path("tomo-homestay")

    limdim = "#room_#{rooms(:limdim).id}"
    assert_select limdim, text: /Anh Minh · 3 khách\s*01\/10–03\/10/
    assert_select "#{limdim} form[action='#{check_in_admin_booking_path(bookings(:limdim_confirmed))}']"
    garden = "#room_#{rooms(:garden).id}"
    assert_select garden, text: /Tiếp theo: Chị Hoa 05\/10/
    assert_select "#{garden} form[action$='/check_in'] button", text: "Nhận phòng sớm"
    assert_select "#{garden} form[data-turbo-confirm='Chị Hoa nhận phòng sớm Garden? Ngày đến đổi 05/10 → 01/10']"

    bookings(:limdim_confirmed).check_in
    get admin_place_path("tomo-homestay")
    assert_select "#{limdim} [data-state]", "Đang có khách"
    assert_select "#{limdim} form[action='#{check_out_admin_booking_path(bookings(:limdim_confirmed))}']"
  end

  test "admins can check in at a homestay they are not a member of" do
    booking = bookings(:limdim_confirmed)
    log_in users(:admin)
    get admin_place_path("tomo-homestay")
    assert_select "#room_#{rooms(:limdim).id} form[action='#{check_in_admin_booking_path(booking)}']"

    post check_in_admin_booking_path(booking), params: { guests: 2 }
    assert booking.reload.checked_in_at
  end

  test "dirty rooms show Chưa dọn and a Dọn xong button, also for staff" do
    rooms(:garden).dirty!
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    log_in staff

    get admin_place_path("tomo-homestay")
    assert_select "#room_#{rooms(:garden).id} .badge", text: "Chưa dọn"
    assert_select "#room_#{rooms(:garden).id} form[action='#{clean_admin_room_path(rooms(:garden))}']"
    assert_select "#room_#{rooms(:limdim).id} .badge", text: "Chưa dọn", count: 0
    assert_select "#room_#{rooms(:limdim).id} form[action='#{check_in_admin_booking_path(bookings(:limdim_confirmed))}']"
  end

  test "a late guest gets call and Không đến, as on the dashboard" do
    bookings(:limdim_confirmed).update!(guest_phone: "0905 123 456")
    travel_to Time.zone.local(2026, 10, 2, 9)
    log_in users(:owner)
    get admin_place_path("tomo-homestay")

    limdim = "#room_#{rooms(:limdim).id}"
    assert_select "#{limdim} .badge", text: "Trễ 1 ngày"
    assert_select "#{limdim} a[href='tel:0905123456']"
    assert_select "#{limdim} form[action='#{no_show_admin_booking_path(bookings(:limdim_confirmed))}']"
    assert_select "#{limdim} form[action='#{check_in_admin_booking_path(bookings(:limdim_confirmed))}']"
  end

  test "early check-in is offered only on a free room, for its next booking" do
    rooms(:limdim).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-07", guest_name: "Sau Anh Minh")
    held = rooms(:garden).bookings.create!(start_date: "2026-10-02", end_date: "2026-10-03", status: "hold", guest_name: "Giữ")
    later = rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-07", guest_name: "Chị Hoa")
    log_in users(:owner)
    get admin_place_path("tomo-homestay")
    assert_select "#room_#{rooms(:garden).id} form[action='#{check_in_admin_booking_path(held)}']", text: "Nhận phòng sớm"
    assert_select "form[action='#{check_in_admin_booking_path(later)}']", count: 0
    assert_select "#room_#{rooms(:limdim).id} button", text: "Nhận phòng sớm", count: 0 # Anh Minh arrives today
  end

  test "early check-in from the homestay page moves the arrival to today" do
    booking = rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-07", guest_name: "Chị Hoa")
    log_in users(:owner)
    post check_in_admin_booking_path(booking), params: { guests: 2 }, headers: { "HTTP_REFERER" => admin_place_url("tomo-homestay") }
    assert_redirected_to admin_place_url("tomo-homestay")
    assert_equal Date.new(2026, 10, 1), booking.reload.start_date
    assert booking.checked_in_at
  end
end
