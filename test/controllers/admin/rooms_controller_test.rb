require "test_helper"

class Admin::RoomsControllerTest < ActionDispatch::IntegrationTest
  setup { log_in users(:owner) }

  test "Phòng lists the rooms of every homestay you own, paused last, with price and OTA channels" do
    rooms(:limdim).update!(price: 450_000)
    rooms(:garden).update!(active: false)
    Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
    get admin_rooms_path
    assert_response :success
    assert_select "aside a.menu-active", text: /Phòng/
    assert_select "section#tomo-homestay h2", "tomo homestay"
    assert_select "section#tomo-homestay a[href='#{new_admin_place_room_path("tomo-homestay")}']", "+ Thêm phòng"
    assert_select "section#tomo-homestay li" do |rows|
      assert_equal [ "room_#{rooms(:limdim).id}", "room_#{rooms(:garden).id}" ], rows.map { it["id"] }
    end
    assert_select "#room_#{rooms(:limdim).id}", text: /Nhận khách.*4 khách · 450\.000 ₫\/đêm · 1 kênh OTA/m
    assert_select "#room_#{rooms(:garden).id}", text: /Tạm ngưng.*chưa có giá · chưa có kênh OTA/m
    assert_select "#room_#{rooms(:limdim).id} a[href='#{edit_admin_room_path(rooms(:limdim))}'][aria-label='Sửa phòng Limdim']", "Sửa"
    assert_select "body", text: /Đồi/, count: 0
  end

  test "Phòng is for owners: staff and admins who own nothing get 403 and no menu entry" do
    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")
    [ staff, users(:admin) ].each do |user|
      delete session_path
      log_in user
      get admin_rooms_path
      assert_response :forbidden
      assert_select "aside a", text: /\APhòng/, count: 0
    end
  end

  test "new form renders" do
    get new_admin_place_room_path("tomo-homestay")
    assert_response :success
    assert_select "h1", "Thêm phòng"
    assert_select "form[novalidate] input[name='room[max_guests]'][value='2']"
    assert_select "input[name='room[active]']", 0
    assert_select "input[type=submit][value='Thêm phòng']"
  end

  test "creates a room in the URL's homestay, ignoring place_id, and parses the price" do
    assert_difference -> { places(:tomo).rooms.count }, 1 do
      post admin_place_rooms_path("tomo-homestay"),
        params: { room: { name: "Mây", max_guests: 2, price: "300.000", active: "1", place_id: places(:hiuhill).id } }
    end
    room = Room.find_by!(name: "Mây")
    assert_equal places(:tomo), room.place
    assert_equal 300_000, room.price
    assert room.active?
    assert_redirected_to edit_admin_room_path(room, anchor: "kenh-ota")
    follow_redirect!
    assert_select "h2#kenh-ota + [role=status]", text: /Đã thêm Phòng Mây\. Phòng này có trên Airbnb/
  end

  test "invalid room re-renders with Vietnamese errors" do
    assert_no_difference -> { Room.count } do
      post admin_place_rooms_path("tomo-homestay"), params: { room: { name: "", max_guests: 0 } }
    end
    assert_response :unprocessable_entity
    assert_select "input[name='room[name]'][aria-invalid=true][autofocus][aria-describedby='name_hint name_error']"
    assert_select "#name_error", "Tên phòng không thể để trống"
    assert_select "#max_guests_error", text: /Số khách tối đa/
  end

  test "a mistyped price comes back as typed, not half-parsed" do
    post admin_place_rooms_path("tomo-homestay"), params: { room: { name: "Mây", max_guests: 2, price: "450kk" } }
    assert_select "input[name='room[price]'][value='450kk'][aria-invalid=true]"
    assert_select "#price_error"
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
    assert_select "h1", "Phòng Garden"
    assert_select "input[type=radio][name='room[active]'][value=true][checked]"

    patch admin_room_path(rooms(:garden)), params: { room: { name: "Vườn", price: "350 000 ₫", place_id: places(:hiuhill).id } }
    rooms(:garden).reload
    assert_equal [ "Vườn", 350_000, places(:tomo) ], [ rooms(:garden).name, rooms(:garden).price, rooms(:garden).place ]
    assert_redirected_to admin_rooms_path(anchor: "tomo-homestay")
  end

  test "switching a room off removes it from public vacancy" do
    original, Rails.cache = Rails.cache, ActiveSupport::Cache::MemoryStore.new
    travel_to Time.zone.local(2026, 10, 5, 12) # both tomo rooms free
    get "/v1/vacancy"
    assert_equal 2, response.parsed_body.dig("places", "tomo-homestay", "left")

    patch admin_room_path(rooms(:garden)), params: { room: { active: "false" } }
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

  test "marks a dirty room clean, but not another owner's room" do
    rooms(:garden).dirty!
    post clean_admin_room_path(rooms(:garden)), headers: { "HTTP_REFERER" => admin_root_url }
    assert_redirected_to admin_root_url
    assert_equal "Đã dọn xong Garden.", flash[:notice]
    assert rooms(:garden).reload.clean?

    other = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2, housekeeping: "dirty")
    post clean_admin_room_path(other)
    assert_response :not_found
    assert other.reload.dirty?
  end

  test "staff can mark a room clean" do
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    delete session_path
    log_in staff
    rooms(:garden).dirty!

    post clean_admin_room_path(rooms(:garden))
    assert rooms(:garden).reload.clean?
  end

  test "admins who aren't members can't mark a room clean" do
    rooms(:garden).dirty!
    delete session_path
    log_in users(:admin)
    post clean_admin_room_path(rooms(:garden))
    assert_response :not_found
    assert rooms(:garden).reload.dirty?
  end

  test "housekeeping can't be set through the room form" do
    patch admin_room_path(rooms(:garden)), params: { room: { name: "Garden", housekeeping: "dirty" } }
    assert rooms(:garden).reload.clean?
  end

  test "changes made in admin are logged with the logged-in user" do
    patch admin_room_path(rooms(:garden)), params: { room: { price: "350.000" } }
    version = rooms(:garden).versions.last
    assert_equal users(:owner).id.to_s, version.whodunnit
    assert_equal [ nil, 350_000 ], version.object_changes["price"]
  end
end
