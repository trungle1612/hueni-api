require "test_helper"

class Admin::BookingsControllerTest < ActionDispatch::IntegrationTest
  def log_in(user)
    post session_path, params: { phone_number: user.phone_number, password: "password123" }
  end

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

  test "creates a manual hold on the picked room, ignoring source" do
    assert_difference -> { rooms(:garden).bookings.count }, 1 do
      post admin_place_bookings_path("tomo-homestay"), params: { booking: {
        room_id: rooms(:garden).id, start_date: "2026-10-05", end_date: "2026-10-07", status: "hold",
        guest_name: "Chị Mai", guest_phone: "0905 123 456", note: "Đến muộn", source: "ical" } }
    end
    booking = Booking.last
    assert_equal [ "hold", "manual", "Chị Mai" ], [ booking.status, booking.source, booking.guest_name ]
    assert_redirected_to admin_place_calendar_path("tomo-homestay")
  end

  test "overlapping booking is rejected" do
    assert_no_difference -> { Booking.count } do
      post admin_place_bookings_path("tomo-homestay"), params: { booking: {
        room_id: rooms(:limdim).id, start_date: "2026-10-02", end_date: "2026-10-04", status: "hold" } }
    end
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Trùng lịch đêm 02\/10 với Anh Minh/
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

  test "edits a manual booking: confirm a hold, then cancel it" do
    booking = rooms(:garden).bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06", status: "hold", guest_phone: "0905123456")
    get edit_admin_booking_path(booking)
    assert_response :success
    assert_select "a[href='tel:0905123456']"

    patch admin_booking_path(booking), params: { booking: { status: "confirmed" } }
    assert booking.reload.confirmed?
    assert_redirected_to admin_place_calendar_path("tomo-homestay")

    patch admin_booking_path(booking), params: { booking: { status: "cancelled" } }
    assert booking.reload.cancelled?
  end

  test "iCal and other owners' bookings cannot be edited" do
    ical = Booking.create!(room: rooms(:limdim), start_date: "2026-10-05", end_date: "2026-10-07", source: "ical",
      calendar_feed: calendar_feeds(:limdim_airbnb), uid: "a")
    other = @other_room.bookings.create!(start_date: "2026-10-05", end_date: "2026-10-06")

    [ ical, other ].each do |booking|
      get edit_admin_booking_path(booking)
      assert_response :not_found
      patch admin_booking_path(booking), params: { booking: { status: "cancelled" } }
      assert_response :not_found
      assert_not booking.reload.cancelled?
    end
  end

  test "checks a guest in and out, then refuses a second tap" do
    booking = bookings(:limdim_confirmed)
    post check_in_admin_booking_path(booking), headers: { "HTTP_REFERER" => admin_root_url }
    assert_redirected_to admin_root_url
    assert_equal "Đã nhận phòng: Anh Minh · Limdim", flash[:notice]
    assert booking.reload.checked_in_at

    post check_in_admin_booking_path(booking)
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
    post check_in_admin_booking_path(booking)
    assert booking.reload.checked_in_at
  end

  test "cannot check in or out another owner's booking" do
    other = @other_room.bookings.create!(start_date: "2026-10-01", end_date: "2026-10-02")
    post check_in_admin_booking_path(other)
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
    post check_in_admin_booking_path(booking)
    assert booking.reload.checked_in_at
  end

  test "check-in fields can't be set through the form; a checked-in booking can't be cancelled" do
    booking = bookings(:limdim_confirmed)
    patch admin_booking_path(booking), params: { booking: { note: "x", checked_in_at: "2026-10-01 10:00", checked_out_at: "2026-10-01 11:00" } }
    assert_nil booking.reload.checked_in_at

    booking.check_in
    patch admin_booking_path(booking), params: { booking: { status: "cancelled" } }
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
    assert_select "button", text: "Huỷ đặt phòng"
  end

  test "edit page of a checked-in guest shows the time and check-out, hides cancel" do
    booking = bookings(:limdim_confirmed)
    booking.check_in
    get edit_admin_booking_path(booking)
    assert_select "#stay", text: /Đã nhận phòng lúc 12:00 01\/10/
    assert_select "#stay form[action='#{check_out_admin_booking_path(booking)}']"
    assert_select "button", text: "Huỷ đặt phòng", count: 0

    booking.check_out
    get edit_admin_booking_path(booking)
    assert_select "#stay", text: /Đã trả phòng lúc 12:00 01\/10 · không sửa được nữa/
    assert_select "#stay form", count: 0
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
end
