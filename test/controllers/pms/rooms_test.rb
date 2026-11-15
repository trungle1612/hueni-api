require "test_helper"

# Phòng, Thêm và sửa phòng in the PWA (#233).
class Pms::RoomsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 2, 9)
    @guest = bookings(:limdim_confirmed) # Limdim 1/10–3/10, Anh Minh
    @guest.update!(price: 200_000)
    @guest.update_columns(checked_in_at: 1.day.ago)
    rooms(:limdim).update!(floor: 1)
    rooms(:garden).update!(floor: 2, housekeeping: "dirty")
  end

  def staff!
    places(:tomo).place_memberships.create!(user: users(:admin), role: "staff")
    log_in users(:admin)
  end

  test "lists rooms by floor with today's state, filters and search" do
    rooms(:garden).bookings.create!(start_date: "2026-10-04", end_date: "2026-10-05", guest_name: "Cô Ba")
    log_in users(:owner)
    get pms_rooms_path
    assert_response :success
    assert_select "header", text: /2 phòng · 2 tầng · tomo homestay/
    assert_select "header a[href=?]", new_pms_room_path, text: "+ Thêm phòng"
    assert_select "nav a[aria-current=page]", text: "Phòng"
    assert_select "section h2", text: "Tầng 1 · 1 phòng"
    assert_select "#room_#{rooms(:limdim).id}", text: /Limdim\s*Anh Minh\s*Đến 03\/10 · còn thu 400.000đ\s*Có khách/
    assert_select "#room_#{rooms(:garden).id}", text: /Garden\s*Cần dọn\s*Cô Ba đến 04\/10/
    assert_select "#room_#{rooms(:garden).id} form[action=?] button", status_pms_room_path(rooms(:garden)), text: "Đã dọn"
    assert_select "nav[aria-label='Lọc theo tình trạng'] a", text: /Có khách\s*1/
    assert_select "#sheet_room_#{rooms(:limdim).id} a[href=?]", pms_booking_path(@guest), text: "Mở đặt phòng của Anh Minh"
    assert_select "#sheet_room_#{rooms(:limdim).id} a[href=?]", edit_pms_room_path(rooms(:limdim))

    get pms_rooms_path(loc: "can-don")
    assert_select "#room_#{rooms(:garden).id}"
    assert_select "#room_#{rooms(:limdim).id}", 0
    get pms_rooms_path(q: "minh")
    assert_select "#room_#{rooms(:limdim).id}"
    assert_select "#room_#{rooms(:garden).id}", 0
    get pms_rooms_path(q: "zzz")
    assert_select "main", text: /Không có phòng khớp “zzz”.*Xoá tìm kiếm/m
  end

  test "Tình trạng: Đã dọn and Bảo trì by staff, the model's refusals shown" do
    staff!
    get pms_rooms_path
    assert_select "header a", text: "+ Thêm phòng", count: 0
    assert_select "a[href=?]", edit_pms_room_path(rooms(:limdim)), count: 0

    patch status_pms_room_path(rooms(:garden)), params: { room: { housekeeping: "clean" } }
    assert rooms(:garden).reload.clean?
    follow_redirect!
    assert_select ".pms-toast", text: "Phòng Garden: đã dọn, sẵn sàng đón khách"

    patch status_pms_room_path(rooms(:limdim)), params: { room: { housekeeping: "maintenance", maintenance_reason: "Hỏng máy lạnh", maintenance_until: "2026-10-05" } }
    follow_redirect!
    assert_select "[role=alert]", text: "Phòng đang có khách. Đổi tình trạng được sau khi trả phòng."
    assert_not rooms(:limdim).reload.maintenance?

    patch status_pms_room_path(rooms(:garden)), params: { room: { housekeeping: "maintenance", maintenance_reason: "", maintenance_until: "2026-10-05" } }
    follow_redirect!
    assert_select "[role=alert]", text: /Lý do bảo trì/
    patch status_pms_room_path(rooms(:garden)), params: { room: { housekeeping: "maintenance", maintenance_reason: "Sơn lại", maintenance_until: "2026-10-05" } }
    follow_redirect!
    assert_select ".pms-toast", text: "Phòng Garden bảo trì đến 05/10"
    assert_select "#room_#{rooms(:garden).id}", text: /Bảo trì\s*Sơn lại · đến 05\/10/
  end

  test "staff get 403 on add, edit and delete" do
    staff!
    get new_pms_room_path
    assert_response :forbidden
    post pms_rooms_path, params: { room: { name: "X", max_guests: 2 } }
    assert_response :forbidden
    get edit_pms_room_path(rooms(:garden))
    assert_response :forbidden
    patch pms_room_path(rooms(:garden)), params: { room: { price: 1 } }
    assert_response :forbidden
    delete pms_room_path(rooms(:garden))
    assert_response :forbidden
    assert_equal 2, places(:tomo).rooms.count
  end

  test "owner adds a room, the model refusing a duplicate name" do
    log_in users(:owner)
    get new_pms_room_path
    assert_select "header h1", "Thêm phòng"
    assert_select "button[form=room_form]", "Thêm phòng"

    post pms_rooms_path, params: { room: { name: "Garden", max_guests: 2 } }
    assert_response :unprocessable_entity
    assert_select "#name_error", text: /Tên phòng|đã/

    post pms_rooms_path, params: { room: { name: "103", floor: 1, room_type: "family", max_guests: 4, price: "450k", weekend_price: "550.000", amenities: [ "", "ac", "desk" ], note: "Gần cầu thang" } }
    assert_redirected_to pms_rooms_path
    room = places(:tomo).rooms.find_by!(name: "103")
    assert_equal [ 1, "family", 4, 450_000, 550_000, %w[ac desk], "Gần cầu thang", true ],
      room.values_at(:floor, :room_type, :max_guests, :price, :weekend_price, :amenities, :note, :active)
    follow_redirect!
    assert_select ".pms-toast", text: "Đã thêm phòng 103"
  end

  test "owner edits a room: change notes, pause, delete only when never booked" do
    rooms(:limdim).bookings.create!(start_date: "2026-10-10", end_date: "2026-10-12", guest_name: "Cô Ba", price: 200_000)
    log_in users(:owner)
    get edit_pms_room_path(rooms(:limdim))
    assert_select "header h1", "Sửa phòng Limdim"
    assert_select "input[type=checkbox][name='room[amenities][]']", Room::AMENITIES.size

    patch pms_room_path(rooms(:limdim)), params: { room: { price: "250k", active: "0" } }
    assert_redirected_to pms_rooms_path
    follow_redirect!
    assert_select ".pms-toast", text: /Đã lưu phòng Limdim\. 2 đặt phòng sắp tới giữ giá cũ\./
    assert_not rooms(:limdim).reload.active?
    assert_select "#room_#{rooms(:limdim).id}", text: /Tạm ngưng/

    delete pms_room_path(rooms(:limdim))
    assert_redirected_to edit_pms_room_path(rooms(:limdim))
    follow_redirect!
    assert_select "[role=alert]", text: "Phòng đã có đặt phòng nên không xoá được."

    spare = places(:tomo).rooms.create!(name: "Nhầm", max_guests: 2)
    delete pms_room_path(spare)
    assert_not Room.exists?(spare.id)
  end

  test "another owner's room is not found" do
    other = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2, housekeeping: "dirty")
    log_in users(:owner)
    get edit_pms_room_path(other)
    assert_response :not_found
    patch pms_room_path(other), params: { room: { name: "X" } }
    assert_response :not_found
    patch status_pms_room_path(other), params: { room: { housekeeping: "clean" } }
    assert_response :not_found
    delete pms_room_path(other)
    assert_response :not_found
    assert other.reload.dirty?
  end
end
