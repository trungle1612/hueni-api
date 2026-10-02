require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  def log_in(user)
    post session_path, params: { email_address: user.email_address, password: "password123" }
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
    assert_select "aside a", text: /Người dùng/, count: 0 # not built yet
  end

  test "shows name, role and avatar initial, including Vietnamese letters" do
    users(:owner).update!(name: "ánh")
    log_in users(:owner)
    get admin_root_path

    assert_select ".avatar", text: "Á"
    assert_select "aside", text: /ánh/
    assert_select "aside", text: /Chủ homestay/
    assert_select "aside button", text: "Đăng xuất"
  end

  test "owner sees only their homestays" do
    log_in users(:owner)
    get admin_root_path
    assert_select "main .card", text: /tomo homestay/
    assert_select "main", text: /6\/24 Kim Long/
    assert_select "main", text: /Hiu Hill Homestay/, count: 0
  end

  test "admin sees every homestay, including ones without an address" do
    log_in users(:admin)
    get admin_root_path
    assert_select "main .card", text: /tomo homestay/
    assert_select "main .card", text: /Hiu Hill Homestay/
    assert_select "main [data-address]", count: 1 # only tomo has an address
  end

  test "cards link to the homestay page and show today's free rooms" do
    travel_to Time.zone.local(2026, 10, 1, 12) # limdim booked, garden free
    log_in users(:owner)
    get admin_root_path
    assert_select "main a[href='#{admin_place_path("tomo-homestay")}']", text: /Còn 1\/2 phòng hôm nay/
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
    assert_select "main .badge", text: "Lỗi đồng bộ (1)"

    users(:owner).place_memberships.destroy_all
    users(:owner).places << places(:hiuhill)
    get admin_root_path
    assert_select "main .badge", text: "Lỗi đồng bộ (1)", count: 1
  end

  test "owner without homestays sees the empty state" do
    users(:owner).place_memberships.destroy_all
    log_in users(:owner)
    get admin_root_path
    assert_select "main", text: /Chưa có homestay nào/
  end
end
