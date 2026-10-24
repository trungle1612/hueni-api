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

  test "a price change says how many upcoming bookings keep their quote, and warns on a cheaper weekend" do
    travel_to Time.zone.local(2026, 10, 1, 12)
    rooms(:garden).update!(price: 400_000)
    rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-07")

    patch admin_room_path(rooms(:garden)), params: { room: { price: "450k", weekend_price: "420k" } }
    assert_equal [ 450_000, 420_000 ], [ rooms(:garden).reload.price, rooms(:garden).weekend_price ]
    assert_equal "Đã lưu phòng Garden. 1 đặt phòng sắp tới giữ giá cũ. Giá thứ 6, thứ 7 đang thấp hơn ngày thường, kiểm tra lại nếu không cố ý.", flash[:notice]
    assert_equal 400_000, rooms(:garden).bookings.last.price
  end

  test "edits own room, price with separators, place_id ignored" do
    get edit_admin_room_path(rooms(:garden))
    assert_select "h1", "Phòng Garden"
    assert_select "input[type=radio][name='room[state]'][value=active][checked]"

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
    delete admin_room_path(rooms(:garden))
    assert_response :forbidden
    assert Room.exists?(rooms(:garden).id)
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

  test "staff set Bảo trì from the homestay page and end it with Xong bảo trì; another owner's room is not found" do
    travel_to Time.zone.local(2026, 10, 5, 12)
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    delete session_path
    log_in staff

    get admin_place_path("tomo-homestay")
    assert_select "#maintenance_room_#{rooms(:garden).id} form[action='#{maintenance_admin_room_path(rooms(:garden))}']"
    patch maintenance_admin_room_path(rooms(:garden)), params: { room: { maintenance_reason: "Hỏng máy lạnh", maintenance_until: "2026-10-07", housekeeping: "clean", price: "1" } }
    assert_redirected_to admin_place_path("tomo-homestay", anchor: "room_#{rooms(:garden).id}")
    assert_equal "Garden bảo trì đến 07/10.", flash[:notice]
    assert_equal [ "maintenance", nil ], rooms(:garden).reload.values_at(:housekeeping, :price)

    get admin_place_path("tomo-homestay")
    assert_select "#room_#{rooms(:garden).id} [data-state]", "Bảo trì"
    assert_select "#room_#{rooms(:garden).id} [data-maintenance]", text: /Bảo trì đến 07\/10 · Hỏng máy lạnh/
    assert_select "#maintenance_room_#{rooms(:garden).id}", 0

    patch maintenance_admin_room_path(rooms(:garden)), params: { room: { maintenance_reason: "", maintenance_until: "2026-10-01" } }
    assert_match "Lý do bảo trì không thể để trống", flash[:alert]

    post clean_admin_room_path(rooms(:garden))
    assert_equal "Xong bảo trì Garden, phòng sẵn sàng.", flash[:notice]
    assert rooms(:garden).reload.clean?

    other = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
    patch maintenance_admin_room_path(other), params: { room: { maintenance_reason: "x", maintenance_until: "2026-10-07" } }
    assert_response :not_found
  end

  test "the room form picks Nhận khách, Bảo trì or Tạm ngưng; Phòng shows Bảo trì" do
    travel_to Time.zone.local(2026, 10, 5, 12)
    patch admin_room_path(rooms(:garden)), params: { room: { state: "maintenance", maintenance_reason: "", maintenance_until: "2026-10-07" } }
    assert_response :unprocessable_entity
    assert_select "#maintenance_reason_error", text: /không thể để trống/
    assert_select "input[name='room[state]'][value=maintenance][checked]"

    patch admin_room_path(rooms(:garden)), params: { room: { state: "maintenance", maintenance_reason: "Sơn lại", maintenance_until: "2026-10-07" } }
    assert_equal [ "maintenance", true, "Sơn lại" ], rooms(:garden).reload.values_at(:housekeeping, :active, :maintenance_reason)
    get admin_rooms_path
    assert_select "#room_#{rooms(:garden).id} .badge", text: "Bảo trì đến 07/10"

    patch admin_room_path(rooms(:garden)), params: { room: { state: "paused", maintenance_reason: "Sơn lại" } }
    assert_equal [ "clean", false, nil ], rooms(:garden).reload.values_at(:housekeeping, :active, :maintenance_reason)

    rooms(:garden).dirty!
    patch admin_room_path(rooms(:garden)), params: { room: { state: "active" } }
    assert_equal [ "dirty", true ], rooms(:garden).reload.values_at(:housekeeping, :active)
  end

  test "Xoá phòng: only a room without bookings, with its feeds; upcoming bookings are listed" do
    travel_to Time.zone.local(2026, 10, 1, 12)
    get edit_admin_room_path(rooms(:limdim))
    assert_select "#xoa-phong", text: /còn 1 đặt phòng sắp tới/
    assert_select "#xoa-phong a[href=?]", edit_admin_booking_path(bookings(:limdim_confirmed)), text: "Anh Minh · 01/10–03/10"
    assert_select "#xoa-phong button", 0

    delete admin_room_path(rooms(:limdim))
    assert_redirected_to edit_admin_room_path(rooms(:limdim), anchor: "xoa-phong")
    assert_equal "Phòng đã có đặt phòng nên không xoá được.", flash[:alert]
    assert Room.exists?(rooms(:limdim).id)

    travel_to Time.zone.local(2026, 10, 10, 12)
    get edit_admin_room_path(rooms(:limdim))
    assert_select "#xoa-phong", text: /không xoá được, để giữ lịch sử/

    rooms(:garden).calendar_feeds.create!(url: "https://1.1.1.1/g.ics", provider: "airbnb")
    get edit_admin_room_path(rooms(:garden))
    assert_select "#xoa-phong form[action=?][data-turbo-confirm='Xoá Phòng Garden? Không hoàn tác được.'] button", admin_room_path(rooms(:garden)), text: "Xoá Phòng Garden"
    assert_difference -> { CalendarFeed.count } => -1 do
      delete admin_room_path(rooms(:garden))
    end
    assert_redirected_to admin_rooms_path(anchor: "tomo-homestay")
    assert_equal "Đã xoá phòng Garden.", flash[:notice]
    assert_not Room.exists?(rooms(:garden).id)

    other = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
    delete admin_room_path(other)
    assert_response :not_found
  end

  test "lowering Số khách tối đa saves and names upcoming bookings with more guests" do
    travel_to Time.zone.local(2026, 10, 1, 12)
    bookings(:limdim_confirmed).update!(guests: 4)
    rooms(:limdim).bookings.create!(start_date: "2026-10-23", end_date: "2026-10-27", guests: 3)
    patch admin_room_path(rooms(:limdim)), params: { room: { max_guests: 2 } }
    assert_equal 2, rooms(:limdim).reload.max_guests
    assert_equal "Đã lưu phòng Limdim. Đặt phòng 01/10–03/10 có 4 khách, nhiều hơn tối đa 2. Đặt phòng 23/10–27/10 có 3 khách, nhiều hơn tối đa 2.", flash[:notice]

    patch admin_room_path(rooms(:limdim)), params: { room: { name: "Limdim" } }
    assert_equal "Đã lưu phòng Limdim.", flash[:notice]
  end

  test "room form saves Tầng, Loại phòng, tiện nghi and ghi chú; Phòng lists type and floor" do
    double = places(:tomo).room_types.create!(name: "Phòng đôi")
    other_type = places(:hiuhill).room_types.create!(name: "Không phải của tôi")
    get edit_admin_room_path(rooms(:garden))
    assert_select "select[name='room[room_type_id]'] option", text: "Phòng đôi"
    assert_select "select[name='room[room_type_id]'] option", text: "Không phải của tôi", count: 0
    assert_select "input[type=checkbox][name='room[amenities][]']", Room::AMENITIES.size

    patch admin_room_path(rooms(:garden)), params: { room: { floor: "2", room_type_id: double.id, amenities: [ "", "balcony", "ac", "pool" ], note: " Vòi sen yếu " } }
    assert_equal [ 2, double, [ "ac", "balcony" ], "Vòi sen yếu" ], rooms(:garden).reload.values_at(:floor, :room_type, :amenities, :note)
    get admin_rooms_path
    assert_select "#room_#{rooms(:garden).id}", text: /Phòng đôi · Tầng 2 · 2 khách/

    patch admin_room_path(rooms(:garden)), params: { room: { room_type_id: other_type.id } }
    assert_response :unprocessable_entity
    assert_equal double, rooms(:garden).reload.room_type
  end

  test "owners manage Loại phòng; a type in use can't be deleted; staff 403, other homestay 404" do
    post admin_place_room_types_path("tomo-homestay"), params: { room_type: { name: "  Phòng   đôi " } }
    assert_redirected_to admin_rooms_path(anchor: "loai-phong-tomo-homestay")
    type = places(:tomo).room_types.sole
    assert_equal "Phòng đôi", type.name
    post admin_place_room_types_path("tomo-homestay"), params: { room_type: { name: "phòng đôi" } }
    assert_equal "Tên loại phòng đã tồn tại", flash[:alert]

    patch admin_place_room_type_path("tomo-homestay", type), params: { room_type: { name: "Phòng 2 người" } }
    assert_equal "Phòng 2 người", type.reload.name
    get admin_rooms_path
    assert_select "#loai-phong-tomo-homestay summary", text: /Phòng 2 người/

    rooms(:garden).update!(room_type: type)
    delete admin_place_room_type_path("tomo-homestay", type)
    assert_equal "Phòng 2 người đang có phòng dùng, đổi loại của các phòng đó trước.", flash[:alert]
    rooms(:garden).update!(room_type: nil)
    delete admin_place_room_type_path("tomo-homestay", type)
    assert_not RoomType.exists?(type.id)

    other = places(:hiuhill).room_types.create!(name: "Đồi")
    patch admin_place_room_type_path("hiuhill-homestay", other), params: { room_type: { name: "x" } }
    assert_response :not_found

    staff = User.create!(name: "Em Hằng", phone_number: "0987111222", password: "password123")
    staff.place_memberships.create!(place: places(:tomo), role: "staff")
    delete session_path
    log_in staff
    post admin_place_room_types_path("tomo-homestay"), params: { room_type: { name: "X" } }
    assert_response :forbidden
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
