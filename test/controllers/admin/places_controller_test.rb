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
    assert_select "#room_#{rooms(:limdim).id} .badge", "Đang có khách"
    assert_select "#room_#{rooms(:garden).id}", text: /chưa có giá/
    assert_select "#room_#{rooms(:garden).id} .badge", "Trống"
    assert_select "a[href='#{new_admin_place_room_path("tomo-homestay")}']", text: /Thêm phòng/
  end

  test "hold shows Giữ chỗ, confirmed wins over hold, switched-off shows Đã tắt" do
    Booking.create!(room: rooms(:garden), start_date: "2026-10-01", end_date: "2026-10-02", status: "hold")
    # Overlaps limdim_confirmed: manual overlaps are rejected, so this only happens alongside an iCal booking.
    Booking.new(room: rooms(:limdim), start_date: "2026-10-01", end_date: "2026-10-02", status: "hold").save!(validate: false)
    log_in users(:owner)
    get admin_place_path("tomo-homestay")
    assert_select "#room_#{rooms(:garden).id} .badge", "Giữ chỗ"
    assert_select "#room_#{rooms(:limdim).id} .badge", "Đang có khách"

    rooms(:garden).update!(active: false)
    get admin_place_path("tomo-homestay")
    assert_select "#room_#{rooms(:garden).id} .badge", "Đã tắt"
  end

  test "another owner's homestay is not found" do
    log_in users(:owner)
    get admin_place_path("hiuhill-homestay")
    assert_response :not_found
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
end
