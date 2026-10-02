require "test_helper"

class Admin::RoomsControllerTest < ActionDispatch::IntegrationTest
  def log_in(user)
    post session_path, params: { phone_number: user.phone_number, password: "password123" }
  end

  setup { log_in users(:owner) }

  test "new form renders" do
    get new_admin_place_room_path("tomo-homestay")
    assert_response :success
    assert_select "h1", "Thêm phòng"
  end

  test "creates a room in the URL's homestay, ignoring place_id, and parses the price" do
    assert_difference -> { places(:tomo).rooms.count }, 1 do
      post admin_place_rooms_path("tomo-homestay"),
        params: { room: { name: "Mây", max_guests: 2, price: "300.000", active: "1", place_id: places(:hiuhill).id } }
    end
    room = Room.find_by!(name: "Mây")
    assert_equal places(:tomo), room.place
    assert_equal 300_000, room.price
    assert_redirected_to admin_place_path("tomo-homestay")
    follow_redirect!
    assert_select "[role=alert]", text: /Đã lưu phòng/
  end

  test "invalid room re-renders with Vietnamese errors" do
    assert_no_difference -> { Room.count } do
      post admin_place_rooms_path("tomo-homestay"), params: { room: { name: "", max_guests: 0 } }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Tên phòng không thể để trống/
  end

  test "cannot add rooms to another owner's homestay" do
    assert_no_difference -> { Room.count } do
      post admin_place_rooms_path("hiuhill-homestay"), params: { room: { name: "X", max_guests: 2 } }
    end
    assert_response :not_found
    get new_admin_place_room_path("hiuhill-homestay")
    assert_response :not_found
  end

  test "edits own room, price with separators, place_id ignored" do
    get edit_admin_room_path(rooms(:garden))
    assert_select "h1", "Sửa phòng"

    patch admin_room_path(rooms(:garden)), params: { room: { name: "Vườn", price: "350 000 ₫", place_id: places(:hiuhill).id } }
    rooms(:garden).reload
    assert_equal [ "Vườn", 350_000, places(:tomo) ], [ rooms(:garden).name, rooms(:garden).price, rooms(:garden).place ]
    assert_redirected_to admin_place_path("tomo-homestay")
  end

  test "switching a room off removes it from public vacancy" do
    original, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
    travel_to Time.zone.local(2026, 10, 5, 12) # both tomo rooms free
    get "/v1/vacancy"
    assert_equal 2, response.parsed_body.dig("places", "tomo-homestay", "left")

    patch admin_room_path(rooms(:garden)), params: { room: { active: "0" } }
    assert_not rooms(:garden).reload.active?

    get "/v1/vacancy"
    assert_equal 1, response.parsed_body.dig("places", "tomo-homestay", "left")
  ensure
    Rails.cache = original
  end

  test "another owner's room cannot be edited or switched" do
    other = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
    get edit_admin_room_path(other)
    assert_response :not_found
    patch admin_room_path(other), params: { room: { active: "0", name: "Hacked" } }
    assert_response :not_found
    assert_equal [ "Đồi", true ], [ other.reload.name, other.active? ]
  end

  test "staff can't add or edit rooms (403); a non-member gets 404" do
    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")
    other = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
    delete session_path
    log_in staff

    get new_admin_place_room_path("tomo-homestay")
    assert_response :forbidden
    assert_select "h1", "Bạn không có quyền"
    post admin_place_rooms_path("tomo-homestay"), params: { room: { name: "X", max_guests: 2 } }
    assert_response :forbidden
    get edit_admin_room_path(rooms(:garden))
    assert_response :forbidden
    patch admin_room_path(rooms(:garden)), params: { room: { active: "0", price: "1" } }
    assert_response :forbidden
    assert rooms(:garden).reload.active?
    assert_not Room.exists?(name: "X")

    get edit_admin_room_path(other) # homestay she isn't a member of
    assert_response :not_found
  end
end
