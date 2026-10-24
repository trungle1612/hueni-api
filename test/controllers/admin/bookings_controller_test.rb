require "test_helper"

class Admin::BookingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    log_in users(:owner)
    travel_to Time.zone.local(2026, 10, 1, 12)
    @other_room = Room.create!(place: places(:hiuhill), name: "Đồi", max_guests: 2)
  end

  test "new form is prefilled from the tapped cell" do
    get new_admin_place_booking_path("tomo-homestay", room_id: rooms(:garden).id, start_date: "2026-10-05")
    assert_response :success
    assert_select "select[name='booking[room_id]'] option[selected][value=?]", rooms(:garden).id.to_s
    assert_select "input[name='booking[start_date]'][value='2026-10-05']"
    assert_select "input[name='booking[end_date]'][value='2026-10-06']"
  end

  test "+ Đặt phòng picks the first room free that night and says so; buttons fit a new booking" do
    rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06", guest_name: "Chị Mai")
    get new_admin_place_booking_path("tomo-homestay", start_date: "2026-10-05")
    assert_select "select[name='booking[room_id]'] option[selected][value=?]", rooms(:limdim).id.to_s, text: "Limdim · tối đa 4 khách"
    assert_select "#availability", text: /✓ Limdim còn trống · 1 đêm \(05\/10–06\/10\)/
    assert_select "label[for=booking_guests]", "Số khách (tối đa 4)"
    assert_select "option[value=?][data-max-guests='2']", rooms(:garden).id.to_s
    assert_select "input[type=submit][value='Đặt phòng']"
    assert_select "a[href=?]", admin_place_calendar_path("tomo-homestay"), text: "Huỷ"
  end

  test "a homestay with one open room shows its name instead of a select" do
    rooms(:garden).update!(active: false)
    get new_admin_place_booking_path("tomo-homestay", start_date: "2026-10-05")
    assert_select "select[name='booking[room_id]']", 0
    assert_select "input[type=hidden][name='booking[room_id]'][value=?]", rooms(:limdim).id.to_s
  end

  test "availability: free, taken with the other free rooms, end before start, and only your own homestay" do
    path = availability_admin_place_bookings_path("tomo-homestay")
    get path, params: { room_id: rooms(:garden).id, start_date: "2026-10-01", end_date: "2026-10-04" }
    assert_select "turbo-frame#availability", text: /✓ Garden còn trống · 3 đêm \(01\/10–04\/10\)/

    get path, params: { room_id: rooms(:limdim).id, start_date: "2026-10-02", end_date: "2026-10-04" }
    assert_select "#dates_error", text: /Trùng lịch đêm 02\/10 với Anh Minh.*Phòng khác còn trống: Garden/m

    get path, params: { room_id: rooms(:limdim).id, start_date: "2026-10-01", end_date: "2026-10-04", booking_id: bookings(:limdim_confirmed).id }
    assert_select "#availability", text: /✓ Không trùng lịch · 3 đêm/ # editing a booking doesn't clash with itself

    get path, params: { room_id: rooms(:garden).id, start_date: "2026-10-04", end_date: "2026-10-04" }
    assert_select "#dates_error", text: "Ngày trả phòng phải sau ngày nhận phòng (ít nhất 1 đêm)"

    get path, params: { room_id: @other_room.id, start_date: "2026-10-01", end_date: "2026-10-02" }
    assert_response :not_found
    get availability_admin_place_bookings_path("hiuhill-homestay"), params: { room_id: @other_room.id, start_date: "2026-10-01", end_date: "2026-10-02" }
    assert_response :not_found
  end

  test "a mistyped phone is shown under the phone field" do
    post admin_place_bookings_path("tomo-homestay"), params: { booking: { room_id: rooms(:garden).id, start_date: "2026-10-05", end_date: "2026-10-06", guest_phone: "09o5" } }
    assert_response :unprocessable_entity
    assert_select "#guest_phone_error", "Số điện thoại không hợp lệ: cần 8–15 chữ số"
    assert_select ".field_with_errors", 0 # would shrink the phone input inside its flex row
    assert_select "input[name='booking[guest_phone]'][value='09o5'][autofocus][aria-invalid=true]"
  end

  test "too many guests is shown under the guest field" do
    post admin_place_bookings_path("tomo-homestay"), params: { booking: { room_id: rooms(:garden).id, start_date: "2026-10-05", end_date: "2026-10-06", guests: 5 } }
    assert_response :unprocessable_entity
    assert_select "#guests_error", "Số khách phải từ 1 đến 2"
    assert_select "input[name='booking[guests]'][autofocus][aria-invalid=true]"
  end

  test "creates a confirmed manual booking on the picked room, ignoring source" do
    assert_difference -> { rooms(:garden).bookings.count }, 1 do
      post admin_place_bookings_path("tomo-homestay"), params: { booking: {
        room_id: rooms(:garden).id, start_date: "2026-10-05", end_date: "2026-10-07",
        guest_name: "Chị Mai", guest_phone: "0905 123 456", note: "Đến muộn", source: "ical" } }
    end
    booking = Booking.last
    assert_equal [ "confirmed", "manual", "Chị Mai" ], [ booking.status, booking.source, booking.guest_name ]
    assert_redirected_to admin_place_calendar_path("tomo-homestay")
    get new_admin_place_booking_path("tomo-homestay")
    assert_select "input[name='booking[status]']", 0 # no Giữ chỗ / Đã xác nhận choice
  end

  test "owners quote a price on the booking; staff can't set one and never see the fields" do
    rooms(:garden).update!(price: 400_000)
    get new_admin_place_booking_path("tomo-homestay", room_id: rooms(:garden).id)
    assert_select "#quote input[name='booking[price]'][placeholder='Giá phòng']"
    assert_select "input[name='booking[weekend_price]']", 0 # a new booking takes the room's weekend price

    post admin_place_bookings_path("tomo-homestay"), params: { booking: { room_id: rooms(:garden).id, start_date: "2026-10-05", end_date: "2026-10-07", price: "350.000" } }
    assert_equal [ 350_000, nil ], Booking.last.then { [ it.price, it.weekend_price ] }
    get edit_admin_booking_path(Booking.last)
    assert_select "#quote input[name='booking[price]'][value='350.000']"
    assert_select "input[name='booking[weekend_price]']"

    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    delete session_path
    log_in staff
    post admin_place_bookings_path("tomo-homestay"), params: { booking: { room_id: rooms(:garden).id, start_date: "2026-10-08", end_date: "2026-10-09", price: "1", deposit: "200k", deposit_method: "bank" } }
    # The room's price, not the staff's; staff note the deposit, saved as the first payment (#139).
    assert_equal [ 400_000, 200_000 ], Booking.last.then { [ it.price, it.paid ] }
    assert_equal [ "bank", "Cọc", staff ], Booking.last.payments.sole.then { [ it.payment_method, it.note, it.user ] }
    get edit_admin_booking_path(Booking.last)
    assert_select "#quote", 0
    assert_select "#thanh-toan", text: /Tiền phòng\s*400.000 ₫/
    assert_select "#thanh-toan", text: /Cọc · Chuyển khoản/
    assert_select "#due", text: /Còn phải thu\s*200.000 ₫/
  end

  test "overlapping booking is rejected" do
    assert_no_difference -> { Booking.count } do
      post admin_place_bookings_path("tomo-homestay"), params: { booking: {
        room_id: rooms(:limdim).id, start_date: "2026-10-02", end_date: "2026-10-04" } }
    end
    assert_response :unprocessable_entity
    assert_select "#availability #dates_error", text: /Trùng lịch đêm 02\/10 với Anh Minh.*Phòng khác còn trống: Garden/m
    assert_select "input[name='booking[start_date]'][autofocus][aria-invalid=true][aria-describedby=dates_error]"
  end

  test "cannot book another owner's room or homestay" do
    assert_no_difference -> { Booking.count } do
      post admin_place_bookings_path("tomo-homestay"), params: { booking: { room_id: @other_room.id, start_date: "2026-10-05", end_date: "2026-10-06" } }
      assert_response :not_found
      post admin_place_bookings_path("hiuhill-homestay"), params: { booking: { room_id: @other_room.id, start_date: "2026-10-05", end_date: "2026-10-06" } }
      assert_response :not_found
    end
    get new_admin_place_booking_path("hiuhill-homestay")
    assert_response :not_found
  end

  test "edits a manual booking: cancel it, then Khôi phục" do
    booking = rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06", guest_phone: "0905123456")
    get edit_admin_booking_path(booking)
    assert_response :success
    assert_select "h1", "Sửa đặt phòng #{booking.code}"
    assert_select "#room_details", 0
    rooms(:garden).update!(amenities: %w[ac bathtub], room_type: "double", note: "chỉ chủ")
    get edit_admin_booking_path(booking)
    assert_select "#room_details", "Phòng đôi · Máy lạnh · Bồn tắm"
    assert_no_match "chỉ chủ", response.body
    assert_match(/\ADP-\d{4}\z/, booking.code)
    assert_select "a[href='tel:0905123456']"

    assert_select "#huy form[action='#{admin_booking_path(booking)}'] input[type=radio][name='booking[cancel_reason]']", 4
    patch admin_booking_path(booking), params: { booking: { status: "cancelled", cancel_reason: "other", cancel_reason_other: "" } }
    assert_response :unprocessable_entity
    assert_select "#huy[open] #cancel_reason_error", text: /không thể để trống/
    assert_select "#cancelled", 0
    assert booking.reload.confirmed?

    patch admin_booking_path(booking), params: { booking: { status: "cancelled", cancel_reason: "Khách huỷ" } }
    assert booking.reload.cancelled?
    assert_redirected_to admin_place_calendar_path("tomo-homestay")
    get edit_admin_booking_path(booking)
    assert_select "#cancelled", text: "Đã huỷ · Khách huỷ"
    assert_select "form[action='#{admin_booking_path(booking)}'] button", text: "Khôi phục đặt phòng"

    patch admin_booking_path(booking), params: { booking: { status: "confirmed" } }
    assert booking.reload.confirmed?
  end

  test "iCal and other owners' bookings cannot be edited" do
    ical = Booking.create!(room: rooms(:limdim), start_date: "2026-10-05", end_date: "2026-10-07", source: "ical",
      calendar_feed: calendar_feeds(:limdim_airbnb), uid: "a")
    other = @other_room.bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06")

    [ ical, other ].each do |booking|
      get edit_admin_booking_path(booking)
      assert_response :not_found
      patch admin_booking_path(booking), params: { booking: { status: "cancelled", cancel_reason: "Khách huỷ" } }
      assert_response :not_found
      assert_not booking.reload.cancelled?
    end
  end

  test "checks a guest in and out, then refuses a second tap" do
    booking = bookings(:limdim_confirmed)
    post check_in_admin_booking_path(booking), params: { guests: 2 }, headers: { "HTTP_REFERER" => admin_root_url }
    assert_redirected_to admin_root_url
    assert_equal "Đã nhận phòng: Anh Minh · Limdim", flash[:notice]
    assert booking.reload.checked_in_at

    post check_in_admin_booking_path(booking), params: { guests: 2 }
    assert_redirected_to admin_root_path
    assert_equal "Khách đã nhận phòng rồi", flash[:alert]

    post check_out_admin_booking_path(booking)
    assert_equal "Đã trả phòng: Anh Minh · Limdim. Phòng chuyển sang chưa dọn.", flash[:notice]
    assert rooms(:limdim).reload.dirty?

    post check_out_admin_booking_path(booking)
    assert_equal "Khách đã trả phòng rồi", flash[:alert]
  end

  test "iCal bookings can be checked in too" do
    booking = calendar_feeds(:limdim_airbnb).bookings.create!(room: rooms(:garden), uid: "x@airbnb", start_date: "2026-10-01", end_date: "2026-10-02", source: "ical")
    post check_in_admin_booking_path(booking), params: { guests: 2 }
    assert booking.reload.checked_in_at
  end

  test "cannot check in or out another owner's booking" do
    other = @other_room.bookings.create!(start_date: "2026-10-01", end_date: "2026-10-02")
    post check_in_admin_booking_path(other), params: { guests: 2 }
    assert_response :not_found
    post check_out_admin_booking_path(other)
    assert_response :not_found
    assert_nil other.reload.checked_in_at
  end

  test "staff can check in and set the guest count" do
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    delete session_path
    log_in staff

    booking = bookings(:limdim_confirmed)
    patch admin_booking_path(booking), params: { booking: { guests: 3 } }
    assert_equal 3, booking.reload.guests
    post check_in_admin_booking_path(booking), params: { guests: 2 }
    assert booking.reload.checked_in_at
  end

  test "check-in fields can't be set through the form; a checked-in booking can't be cancelled" do
    booking = bookings(:limdim_confirmed)
    patch admin_booking_path(booking), params: { booking: { note: "x", checked_in_at: "2026-10-01 10:00", checked_out_at: "2026-10-01 11:00" } }
    assert_nil booking.reload.checked_in_at

    booking.check_in
    patch admin_booking_path(booking), params: { booking: { status: "cancelled", cancel_reason: "Khách huỷ" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Khách đã nhận phòng, không huỷ được/
    assert booking.reload.confirmed?
  end

  test "edit page shows the guest count field and a confirmed check-in button" do
    booking = bookings(:limdim_confirmed)
    get edit_admin_booking_path(booking)
    assert_select "input[name='booking[guests]'][type=number][max='4']"
    assert_select "#stay form[action='#{check_in_admin_booking_path(booking)}'][data-turbo-confirm='Anh Minh nhận phòng Limdim?']"
    assert_select "form[action='#{check_out_admin_booking_path(booking)}']", count: 0
    assert_select "#huy summary", text: "Huỷ đặt phòng"
  end

  test "edit page of a checked-in guest shows the time and check-out, hides cancel" do
    booking = bookings(:limdim_confirmed)
    booking.check_in
    get edit_admin_booking_path(booking)
    assert_select "#stay", text: /Đã nhận phòng lúc 12:00 01\/10/
    assert_select "#stay form[action='#{check_out_admin_booking_path(booking)}']"
    assert_select "#huy", count: 0

    booking.check_out
    get edit_admin_booking_path(booking)
    assert_select "#stay", text: /Đã trả phòng lúc 12:00 01\/10 · không sửa được nữa/
    assert_select "#stay form", count: 1
    assert_select "#stay form[action='#{undo_check_out_admin_booking_path(booking)}']", text: "Hoàn tác"
    assert_select "fieldset[disabled] input[name='booking[guest_name]']"
    assert_select "input[type=submit][value='Lưu']", count: 0
  end

  test "a checked-out booking can't be updated" do
    booking = bookings(:limdim_confirmed)
    booking.check_in
    booking.check_out
    patch admin_booking_path(booking), params: { booking: { guest_name: "Đổi", end_date: "2026-10-10" } }
    assert_redirected_to edit_admin_booking_path(booking)
    assert_equal "Khách đã trả phòng, không sửa được đặt phòng.", flash[:alert]
    assert_equal [ "Anh Minh", Date.new(2026, 10, 3) ], booking.reload.values_at(:guest_name, :end_date)
  end

  test "creates a booking with a guest count" do
    post admin_place_bookings_path("tomo-homestay"), params: { booking: { room_id: rooms(:garden).id, start_date: "2026-10-05", end_date: "2026-10-06", guests: 2 } }
    assert_equal 2, Booking.last.guests
  end

  test "staff can mark a late guest as a no-show; another owner's booking is not found" do
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    delete session_path
    log_in staff
    booking = bookings(:limdim_confirmed) # 1/10–3/10

    travel_to Time.zone.local(2026, 10, 2, 9) do
      post no_show_admin_booking_path(booking), headers: { "HTTP_REFERER" => admin_root_url }
      assert_redirected_to admin_root_url
      assert_equal "Đã huỷ (không đến): Anh Minh · Limdim", flash[:notice]
      assert booking.reload.cancelled?

      post no_show_admin_booking_path(booking)
      assert_equal "Đặt phòng đã huỷ", flash[:alert]

      other = @other_room.bookings.create!(start_date: "2026-10-01", end_date: "2026-10-03")
      post no_show_admin_booking_path(other)
      assert_response :not_found
      assert_not other.reload.cancelled?
    end
  end

  test "owners undo a check-in and a check-out from the booking page" do
    booking = bookings(:limdim_confirmed)
    booking.check_in
    get edit_admin_booking_path(booking)
    assert_select "#stay form[action='#{undo_check_in_admin_booking_path(booking)}'][data-turbo-confirm*='Hoàn tác nhận phòng']"

    post undo_check_in_admin_booking_path(booking), headers: { "HTTP_REFERER" => edit_admin_booking_url(booking) }
    assert_redirected_to edit_admin_booking_url(booking)
    assert_equal "Đã hoàn tác nhận phòng: Anh Minh · Limdim", flash[:notice]
    assert_nil booking.reload.checked_in_at

    booking.check_in
    booking.check_out
    post undo_check_out_admin_booking_path(booking)
    assert_equal "Đã hoàn tác trả phòng: Anh Minh · Limdim", flash[:notice]
    assert booking.reload.can_check_out?

    post undo_check_out_admin_booking_path(booking)
    assert_equal "Khách chưa trả phòng", flash[:alert]
  end

  test "staff can't undo (403, no button); another owner's booking is not found" do
    booking = bookings(:limdim_confirmed)
    booking.check_in
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    delete session_path
    log_in staff
    get edit_admin_booking_path(booking)
    assert_select "#stay button", text: "Hoàn tác", count: 0
    post undo_check_in_admin_booking_path(booking)
    assert_response :forbidden
    assert booking.reload.checked_in_at

    other = @other_room.bookings.create!(start_date: "2026-10-01", end_date: "2026-10-02")
    post undo_check_in_admin_booking_path(other)
    assert_response :not_found
  end

  test "staff move an in-house guest from the booking page; other homestays' rooms are not found" do
    booking = rooms(:garden).bookings.create!(start_date: "2026-10-01", end_date: "2026-10-02", guest_name: "Chị Mai")
    booking.check_in
    get edit_admin_booking_path(booking)
    assert_select "#move", count: 0 # limdim is taken by Anh Minh

    bookings(:limdim_confirmed).update!(status: "cancelled", cancel_reason: "Khách huỷ")
    staff = User.create!(name: "Bé Na", phone_number: "0987654321", password: "password123")
    places(:tomo).place_memberships.create!(user: staff, role: "staff")
    delete session_path
    log_in staff
    get edit_admin_booking_path(booking)
    assert_select "#move option", text: "Limdim"

    post move_admin_booking_path(booking), params: { room_id: @other_room.id }
    assert_response :not_found

    post move_admin_booking_path(booking), params: { room_id: rooms(:limdim).id }, headers: { "HTTP_REFERER" => edit_admin_booking_url(booking) }
    assert_redirected_to edit_admin_booking_url(booking)
    assert_equal "Đã đổi phòng: Chị Mai · Garden → Limdim. Phòng Garden chuyển sang chưa dọn.", flash[:notice]
    assert_equal rooms(:limdim), booking.reload.room
  end

  test "check-in asks for the head count when the booking has none" do
    booking = bookings(:limdim_confirmed)
    get edit_admin_booking_path(booking)
    assert_select "#stay form[action='#{check_in_admin_booking_path(booking)}'] input[name=guests][required][max='4']"

    post check_in_admin_booking_path(booking)
    assert_equal "Nhập số khách khi nhận phòng", flash[:alert]
    assert_nil booking.reload.checked_in_at

    post check_in_admin_booking_path(booking), params: { guests: 9 }
    assert_equal "Số khách phải từ 1 đến 4", flash[:alert]

    booking.update!(guests: 3)
    get edit_admin_booking_path(booking)
    assert_select "#stay input[name=guests]", count: 0
    post check_in_admin_booking_path(booking)
    assert booking.reload.checked_in_at
    assert_equal 3, booking.guests
  end

  test "staff mark the lưu trú declaration; another owner's booking is not found" do
    booking = bookings(:limdim_confirmed)
    booking.check_in(guests: 2)
    get edit_admin_booking_path(booking)
    assert_select "#stay form[action='#{declare_admin_booking_path(booking)}']", text: "Đã khai báo"

    post declare_admin_booking_path(booking)
    assert_equal "Đã khai báo lưu trú: Anh Minh · Limdim", flash[:notice]
    assert booking.reload.declared_at

    other = @other_room.bookings.create!(start_date: "2026-10-01", end_date: "2026-10-02")
    post declare_admin_booking_path(other)
    assert_response :not_found
  end

  test "admins who aren't members can't open a booking or act on it" do
    booking = bookings(:limdim_confirmed)
    in_house = rooms(:garden).bookings.create!(start_date: "2026-10-01", end_date: "2026-10-02", guests: 1)
    in_house.check_in
    delete session_path
    log_in users(:admin)

    get edit_admin_booking_path(booking)
    assert_response :not_found

    { check_in: booking, no_show: booking, check_out: in_house, undo_check_in: in_house, declare: in_house }.each do |action, target|
      post public_send("#{action}_admin_booking_path", target), params: { guests: 2 }
      assert_response :not_found, action
    end
    post move_admin_booking_path(in_house), params: { room_id: rooms(:limdim).id }
    assert_response :not_found
    assert_nil booking.reload.checked_in_at
    assert_not booking.cancelled?
    assert_equal [ rooms(:garden), nil, nil ], in_house.reload.values_at(:room, :checked_out_at, :declared_at)
  end

  test "an admin who is a staff member works the desk but can't undo" do
    booking = bookings(:limdim_confirmed)
    users(:admin).place_memberships.create!(place: places(:tomo), role: "staff")
    delete session_path
    log_in users(:admin)
    post check_in_admin_booking_path(booking), params: { guests: 2 }
    assert booking.reload.checked_in_at
    post undo_check_in_admin_booking_path(booking)
    assert_response :forbidden
  end
end
